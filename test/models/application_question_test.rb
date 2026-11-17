require "test_helper"

class ApplicationQuestionTest < ActiveSupport::TestCase
  setup do
    @guild = Guild.create!(id: 555_000_111_222_333_444, name: "Raid Server")
    @team = ActsAsTenant.with_tenant(@guild) do
      Team.create!(name: "Alpha", team_role_id: 1, officer_role_id: 2, review_channel_id: 3)
    end
  end

  def build(**attrs)
    ActsAsTenant.with_tenant(@guild) { @team.application_questions.build(key: "q", label: "Raid experience", **attrs) }
  end

  test "a description is optional" do
    assert build.valid?
    assert build(description: "").valid?
  end

  test "a description may use Discord's full 100 chars — far past the 45-char label cap" do
    assert build(description: "x" * ApplicationQuestion::DESCRIPTION_MAX).valid?

    question = build(description: "x" * (ApplicationQuestion::DESCRIPTION_MAX + 1))
    assert_not question.valid?
    assert question.errors.added?(:description, :too_long, count: ApplicationQuestion::DESCRIPTION_MAX)
  end
end

class ApplicationQuestionChoiceTest < ActiveSupport::TestCase
  setup do
    @guild = Guild.create!(id: 555_000_111_222_333_444, name: "Raid Server")
    @team = ActsAsTenant.with_tenant(@guild) do
      Team.create!(name: "Alpha", team_role_id: 1, officer_role_id: 2, review_channel_id: 3)
    end
  end

  def build(**attrs)
    ActsAsTenant.with_tenant(@guild) { @team.application_questions.build(key: "q", label: "Roles", **attrs) }
  end

  # Stands in for a modal submit / WebSubmission: value(key) and values(key).
  Source = Struct.new(:value_answer, :values_answer) do
    def value(_key) = value_answer
    def values(_key) = values_answer
  end

  test "options are entered one per line, trimmed, with blanks and repeats dropped" do
    question = build(style: :choice, options_text: " Tank \n\nHealer\nTank\nDPS\n")

    assert_equal %w[Tank Healer DPS], question.options
    assert_equal "Tank\nHealer\nDPS", question.options_text
  end

  test "multiple choice needs 2–10 options — Discord's radio group bounds" do
    assert_not build(style: :choice, options_text: "Tank").valid?
    assert build(style: :choice, options_text: "Tank\nHealer").valid?
    assert_not build(style: :choice, options_text: (1..11).map { "Option #{_1}" }.join("\n")).valid?
  end

  test "checkboxes need 1–10 options — Discord's checkbox group bounds" do
    assert_not build(style: :checkboxes, options_text: "").valid?
    assert build(style: :checkboxes, options_text: "I agree to the raid rules").valid?
    assert_not build(style: :checkboxes, options_text: (1..11).map { "Option #{_1}" }.join("\n")).valid?
  end

  test "an option over Discord's 100 chars is refused" do
    question = build(style: :checkboxes, options_text: "x" * (ApplicationQuestion::OPTION_MAX + 1))

    assert_not question.valid?
    assert_match(/at most 100 characters/, question.errors.full_messages.to_sentence)
  end

  test "each style keeps only the settings it uses" do
    text = build(style: :short, options_text: "Tank\nHealer", placeholder: "hint", max_length: 50)
    assert text.valid?
    assert_empty text.options
    assert_equal "hint", text.placeholder

    choice = build(style: :choice, options_text: "Tank\nHealer", placeholder: "hint", min_length: 1, max_length: 50)
    assert choice.valid?
    assert_nil choice.placeholder
    assert_nil choice.min_length
    assert_nil choice.max_length
  end

  test "a yes/no question is never required — Discord can't require a checkbox" do
    question = build(style: :yes_no, required: true)

    assert question.valid?
    assert_not question.required
  end

  test "a multiple-choice answer is kept only if it's one of the options" do
    question = build(style: :choice, options_text: "Tank\nHealer")

    assert_equal "Healer", question.answer_from(Source.new("Healer"))
    assert_equal "", question.answer_from(Source.new("Sneaky"))
    assert_equal "", question.answer_from(Source.new(nil))
  end

  test "checkbox answers keep the offered ones, in the question's order" do
    question = build(style: :checkboxes, options_text: "Tank\nHealer\nDPS")

    assert_equal "Tank, DPS", question.answer_from(Source.new(nil, %w[DPS Sneaky Tank]))
    assert_equal "", question.answer_from(Source.new(nil, []))
    assert_equal "", question.answer_from(Source.new(nil, nil))
  end

  test "a yes/no answer reads Discord's boolean and the web form's 1/0" do
    question = build(style: :yes_no)

    assert_equal "Yes", question.answer_from(Source.new(true))
    assert_equal "No", question.answer_from(Source.new(false))
    assert_equal "Yes", question.answer_from(Source.new("1"))
    assert_equal "No", question.answer_from(Source.new("0"))
    assert_equal "No", question.answer_from(Source.new(nil))
  end
end
