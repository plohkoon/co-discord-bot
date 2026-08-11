require "test_helper"

# Correcting a mistyped character from the DM the applicant receives.
#
# This flow exists because of one Discord asymmetry: a BUTTON may open a modal,
# a MODAL SUBMIT may not. So the application can never be rejected at submit
# time to make someone fix a typo — correction has to live on a follow-up
# message instead.
class FixCharacterTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  APPLICANT = 555_000_111_222_333_444
  STRANGER  = 999_888_777_666_555_444

  FakeUser = Struct.new(:id)

  # Stands in for a component/modal interaction arriving in a DM: no server.
  class FakeEvent
    attr_reader :user, :responses, :modals

    def initialize(user_id, values: {})
      @user = FakeUser.new(user_id)
      @values = values
      @responses = []
      @modals = []
    end

    def server = nil
    def value(key) = @values[key]
    def respond(content: nil, **) = @responses << content
    def show_modal(title:, custom_id:, &block) = @modals << { title: title, custom_id: custom_id }
  end

  def guild = @guild ||= Guild.create!(id: 777_000_111_222_333_444, name: "Raid Server")

  def team
    @team ||= ActsAsTenant.with_tenant(guild) do
      Team.create!(name: "Alpha", team_role_id: 1, officer_role_id: 2, review_channel_id: 3)
    end
  end

  def application(input: "Thral-Sargeras", status: :pending)
    @application ||= ActsAsTenant.with_tenant(guild) do
      membership = TeamMembership.create!(team: team, discord_user_id: APPLICANT,
                                          discord_username: "applicant")
      membership.team_applications.create!(
        team: team, discord_user_id: APPLICANT, discord_username: "applicant",
        character_input: input, character_resolved_at: Time.current, status: status
      )
    end
  end

  def run_component(klass, user_id: APPLICANT, values: {}, id: application.id)
    event = FakeEvent.new(user_id, values: values)
    resolved = klass.guild_from_params(application_id: id.to_s)
    ActsAsTenant.with_tenant(resolved || guild) do
      klass.new(event: event, guild: resolved || guild, params: { application_id: id.to_s }).process
    end
    event
  end

  # --- The DM tenant problem ---
  #
  # A DM carries no guild_id, so the runner's usual tenant lookup refuses. These
  # handlers name their own guild from the custom_id; without that the button
  # would answer "I can't find this server".

  test "the handlers resolve their guild from the application, not the event" do
    assert Commands::Components::FixCharacter.in_dm?
    assert Commands::Components::FixCharacterModal.in_dm?
    assert_equal guild, Commands::Components::FixCharacter.guild_from_params(application_id: application.id.to_s)
  end

  test "an unknown application resolves no guild rather than raising" do
    assert_nil Commands::Components::FixCharacter.guild_from_params(application_id: "999999")
    assert_nil Commands::Components::FixCharacter.guild_from_params({})
  end

  # --- The button ---

  test "the button opens a modal prefilled with what they typed" do
    event = run_component(Commands::Components::FixCharacter)

    assert_equal 1, event.modals.size
    assert_match(/Alpha/, event.modals.first[:title])
    assert_match(/fixcharmodal/, event.modals.first[:custom_id])
  end

  # The button lives in a DM, but a custom_id is guessable — the handler has to
  # check who is pressing it.
  test "someone else's button press opens nothing" do
    event = run_component(Commands::Components::FixCharacter, user_id: STRANGER)

    assert_empty event.modals
    assert_match(/no longer open/i, event.responses.first)
  end

  test "a decided application can no longer be corrected" do
    app = application(status: :accepted)
    event = run_component(Commands::Components::FixCharacter, id: app.id)

    assert_empty event.modals
    assert_match(/no longer open/i, event.responses.first)
  end

  # --- The modal ---

  test "a corrected character is stored and re-resolved" do
    app = application
    assert_enqueued_with(job: ApplicationCharacterJob) do
      run_component(Commands::Components::FixCharacterModal, values: { "character" => " Thrall-Sargeras " })
    end

    app.reload
    assert_equal "Thrall-Sargeras", app.character_input
    # Cleared so the review message reads "Loading…" rather than leaving the old
    # failure on screen while this is looked up again.
    assert_nil app.character_resolved_at
    assert app.character_pending?
    assert_not app.character_unresolved?
  end

  test "a blank correction is refused without queueing work" do
    assert_no_enqueued_jobs only: ApplicationCharacterJob do
      event = run_component(Commands::Components::FixCharacterModal, values: { "character" => "  " })
      assert_match(/Name-Realm/i, event.responses.first)
    end

    assert_equal "Thral-Sargeras", application.reload.character_input, "the old value is kept"
  end

  test "someone else cannot submit a correction" do
    assert_no_enqueued_jobs only: ApplicationCharacterJob do
      run_component(Commands::Components::FixCharacterModal, user_id: STRANGER,
                    values: { "character" => "Thrall-Sargeras" })
    end

    assert_equal "Thral-Sargeras", application.reload.character_input
  end

  # A second typo must be no more of a dead end than the first: the correction
  # goes through the same job, which sends the same DM with the same button.
  test "a correction that also fails is itself correctable" do
    app = application
    run_component(Commands::Components::FixCharacterModal, values: { "character" => "Thrallll-Sargeras" })

    sent = []
    stub_singleton_method(Notifications::DirectMessage, :call, ->(**args) { sent << args }) do
      stub_singleton_method(BattleNet::Client, :app, ->(**) {
        Class.new { def character_profile(*) = raise(BattleNet::Client::NotFound) }.new
      }) do
        ApplicationCharacterJob.perform_now(application_id: app.id, guild_id: guild.id)
      end
    end

    assert_equal 1, sent.size
    assert sent.first[:components].present?, "the follow-up carries another Fix character button"
    assert app.reload.character_unresolved?
  end
end
