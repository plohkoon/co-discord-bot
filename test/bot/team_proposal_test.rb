require "test_helper"

# "Apply to make a team": the button beside a roster category header opens the
# fixed questionnaire, and submitting saves a TeamProposal and hands the post
# to TeamProposalPostJob. /guild category edit turns it on and off; the guild
# holds the one channel every proposal goes to.
class TeamProposalTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  # Records what a modal would contain: each label and its text input.
  class FakeModal
    attr_reader :inputs

    def initialize = @inputs = []

    def label(label:, description: nil)
      input = { label: label, description: description }
      yield(Class.new do
        define_method(:text_input) { |**opts| input.merge!(opts) }
      end.new)
      @inputs << input
    end
  end

  class FakeUser
    def initialize(admin: false) = @admin = admin
    def id = 42
    def username = "thrall"
    def permission?(kind) = @admin && kind == :manage_server
  end

  class FakeEvent
    attr_reader :options, :responses, :modals

    def initialize(options: {}, values: {}, admin: false)
      @options = options
      @values = values
      @admin = admin
      @responses = []
      @modals = []
    end

    def user = FakeUser.new(admin: @admin)
    def server = nil
    def value(key) = @values[key]
    def respond(content: nil, **) = @responses << content

    def show_modal(title:, custom_id:)
      modal = FakeModal.new
      yield modal
      @modals << { title: title, custom_id: custom_id, inputs: modal.inputs }
    end
  end

  def guild = @guild ||= Guild.create!(id: 555_000_111_222_333_444, name: "Raid Server", team_proposals_channel_id: 900)

  setup do
    @category = ActsAsTenant.with_tenant(guild) do
      TeamCategory.create!(name: "Retail PvE Teams", proposals_enabled: true)
    end
  end

  def dispatch(klass, event, params: {})
    ActsAsTenant.with_tenant(guild) { klass.new(event: event, guild: guild, params: params).process }
    event
  end

  def answers = TeamProposal::QUESTIONS.to_h { |q| [ q[:key], "  #{q[:key]} answer  " ] }

  test "the button opens the five-question modal" do
    event = dispatch(Commands::Components::ProposeTeamButton, FakeEvent.new, params: { category_id: @category.id.to_s })

    modal = event.modals.sole
    assert_equal "proposal:#{@category.id}", modal[:custom_id]
    assert_match(/Retail PvE Teams/, modal[:title])
    assert_equal TeamProposal::QUESTIONS.map { |q| q[:key] }, modal[:inputs].map { |i| i[:custom_id] }
    modal[:inputs].each do |input|
      assert_operator input[:label].size, :<=, 45, "Discord caps modal labels at 45 chars"
      assert_operator input[:description].to_s.size, :<=, 100, "Discord caps label descriptions at 100 chars"
    end
  end

  test "the button refuses once the category stops taking proposals" do
    @category.update!(proposals_enabled: false)

    event = dispatch(Commands::Components::ProposeTeamButton, FakeEvent.new, params: { category_id: @category.id.to_s })

    assert_empty event.modals
    assert_match(/isn't taking new team proposals/, event.responses.sole)
  end

  test "submitting saves the proposal and enqueues its post" do
    event = nil
    assert_enqueued_with(job: TeamProposalPostJob) do
      event = dispatch(Commands::Components::ProposeTeamModal, FakeEvent.new(values: answers),
                  params: { category_id: @category.id.to_s })
    end

    proposal = ActsAsTenant.with_tenant(guild) { TeamProposal.sole }
    assert_equal @category, proposal.team_category
    assert_equal 42, proposal.discord_user_id
    assert_equal "thrall", proposal.discord_username
    assert_equal TeamProposal::QUESTIONS.map { |q| q[:label] }, proposal.answers.map { |a| a["label"] }
    assert_equal "team answer", proposal.answers.first["answer"] # stripped
    assert_match(/sent to the server admins/, event.responses.sole)
  end

  test "a submit after the guild's proposals channel was cleared saves nothing" do
    guild.update!(team_proposals_channel_id: nil)

    dispatch(Commands::Components::ProposeTeamModal, FakeEvent.new(values: answers), params: { category_id: @category.id.to_s })

    assert_equal 0, ActsAsTenant.with_tenant(guild) { TeamProposal.count }
    assert_no_enqueued_jobs(only: TeamProposalPostJob)
  end

  # --- /guild category edit ---

  def edit(**options)
    dispatch(Commands::Guild::Category::Edit,
        FakeEvent.new(options: { "category" => "Retail PvE Teams" }.merge(options.transform_keys(&:to_s)), admin: true))
  end

  test "edit sets the about text, and 'none' clears it" do
    edit(about: "Our retail PvE teams.")
    assert_equal "Our retail PvE teams.", @category.reload.about

    edit(about: "None")
    assert_nil @category.reload.about
  end

  test "edit toggles proposals off and back on" do
    event = edit(proposals: false)
    assert_not @category.reload.proposals_enabled?
    assert_match(/proposals turned off/, event.responses.sole)

    event = edit(proposals: true)
    assert @category.reload.proposals_enabled?
    assert_match(/team proposals turned on\./, event.responses.sole)
  end

  test "turning proposals on with no guild channel set says where to set one" do
    guild.update!(team_proposals_channel_id: nil)
    @category.update!(proposals_enabled: false)

    event = edit(proposals: true)

    assert @category.reload.proposals_enabled?
    assert_match(/once a team-proposals channel is set on the web dashboard/, event.responses.sole)
  end
end
