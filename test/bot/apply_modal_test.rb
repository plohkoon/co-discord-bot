require "test_helper"

# The application modal (/team apply and the roster Apply button share it via
# Commands::ApplyFlow): each question becomes a Label wrapping the component
# for its style, and a question's description rides along under the 45-char
# label. Built through discordrb's real LabelBuilder, so these assert the
# payload Discord actually receives.
class ApplyModalTest < ActiveSupport::TestCase
  RADIO_GROUP    = 21
  CHECKBOX_GROUP = 22
  CHECKBOX       = 23
  TEXT_INPUT     = 4

  class FakeModal
    attr_reader :inputs

    def initialize = @inputs = []

    def label(**opts, &block)
      @inputs << Discordrb::Webhooks::Modal::LabelBuilder.new(**opts, &block).to_h
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
    @team = ActsAsTenant.with_tenant(@guild) do
      Team.create!(name: "Alpha", team_role_id: 1, officer_role_id: 2, review_channel_id: 3)
    end
  end

  def add_question(**attrs)
    ActsAsTenant.with_tenant(@guild) do
      @team.application_questions.create!(position: @team.application_questions.count, **attrs)
    end
  end

  def open_modal
    event = FakeEvent.new
    ActsAsTenant.with_tenant(@guild) do
      Commands::Components::ApplyButton.new(event: event, guild: @guild, params: { team_id: @team.id.to_s }).process
    end
    event.modals.sole
  end

  def input_for(question) = open_modal[:inputs].find { |i| i[:component][:custom_id] == "q:#{question.id}" }

  test "a question's description is shown under its label" do
    question = add_question(key: "exp", label: "Raid experience",
                            description: "Which tiers have you cleared, on what difficulty, and with which guild?")
    input = input_for(question)

    assert_equal "Raid experience", input[:label]
    assert_equal "Which tiers have you cleared, on what difficulty, and with which guild?", input[:description]
  end

  test "a blank description is left off rather than sent empty" do
    question = add_question(key: "why", label: "Why join?", description: "")

    assert_not input_for(question).key?(:description)
  end

  test "text questions are still text inputs" do
    question = add_question(key: "why", label: "Why join?", style: :paragraph, max_length: 500, placeholder: "Tell us")
    component = input_for(question)[:component]

    assert_equal TEXT_INPUT, component[:type]
    assert_equal 500, component[:max_length]
    assert_equal "Tell us", component[:placeholder]
  end

  test "multiple choice is a radio group of the question's options" do
    question = add_question(key: "role", label: "Main role", style: :choice, options_text: "Tank\nHealer\nDPS")
    component = input_for(question)[:component]

    assert_equal RADIO_GROUP, component[:type]
    assert_equal true, component[:required]
    # Only value + label per option: no null description/default keys.
    assert_equal [ { value: "Tank", label: "Tank" }, { value: "Healer", label: "Healer" }, { value: "DPS", label: "DPS" } ],
                 component[:options]
  end

  test "checkboxes are a checkbox group; an optional one allows ticking none" do
    required = add_question(key: "roles", label: "Roles you can play", style: :checkboxes, options_text: "Tank\nHealer")
    optional = add_question(key: "days", label: "Extra days", style: :checkboxes, options_text: "Fri\nSat", required: false)

    component = input_for(required)[:component]
    assert_equal CHECKBOX_GROUP, component[:type]
    assert_equal true, component[:required]
    # Discord: min_values must be omitted or >= 1 when required.
    assert_not component.key?(:min_values)

    component = input_for(optional)[:component]
    assert_equal false, component[:required]
    assert_equal 0, component[:min_values]
  end

  test "yes/no is a single checkbox" do
    question = add_question(key: "nights", label: "Can you raid 2 nights a week?", style: :yes_no)
    component = input_for(question)[:component]

    assert_equal CHECKBOX, component[:type]
    assert_equal "q:#{question.id}", component[:custom_id]
  end
end
