require "test_helper"

# The application modal (/team apply and the roster Apply button share it via
# Commands::ApplyFlow): each question becomes a label + text input, and a
# question's description rides along under the 45-char label.
class ApplyModalTest < ActiveSupport::TestCase
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
    def id = 42
    def username = "thrall"
    def permission?(_kind) = false
  end

  class FakeEvent
    attr_reader :responses, :modals

    def initialize
      @responses = []
      @modals = []
    end

    def user = FakeUser.new
    def server = nil
    def options = {}
    def respond(content: nil, **) = @responses << content

    def show_modal(title:, custom_id:)
      modal = FakeModal.new
      yield modal
      @modals << { title: title, custom_id: custom_id, inputs: modal.inputs }
    end
  end

  setup do
    @guild = Guild.create!(id: 555_000_111_222_333_444, name: "Raid Server")
    ActsAsTenant.with_tenant(@guild) do
      @team = Team.create!(name: "Alpha", team_role_id: 1, officer_role_id: 2, review_channel_id: 3)
      @with = @team.application_questions.create!(
        position: 0, key: "exp", label: "Raid experience",
        description: "Which tiers have you cleared, on what difficulty, and with which guild?"
      )
      @without = @team.application_questions.create!(position: 1, key: "why", label: "Why join?", description: "")
    end
  end

  def open_modal
    event = FakeEvent.new
    ActsAsTenant.with_tenant(@guild) do
      Commands::Components::ApplyButton.new(event: event, guild: @guild, params: { team_id: @team.id.to_s }).process
    end
    event.modals.sole
  end

  test "a question's description is shown under its label" do
    input = open_modal[:inputs].find { |i| i[:custom_id] == "q:#{@with.id}" }

    assert_equal "Raid experience", input[:label]
    assert_equal "Which tiers have you cleared, on what difficulty, and with which guild?", input[:description]
  end

  test "a blank description is left off rather than sent empty" do
    input = open_modal[:inputs].find { |i| i[:custom_id] == "q:#{@without.id}" }

    assert_equal "Why join?", input[:label]
    assert_nil input[:description]
  end
end
