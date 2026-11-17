require "test_helper"

# The web question editor: the description field (the room a long prompt needs,
# since Discord caps the question label at 45 chars) saves and clears.
class TeamQuestionsTest < ActionDispatch::IntegrationTest
  setup do
    @guild = Guild.create!(id: 555_000_111_222_333_444, name: "Raid Server")
    ActsAsTenant.with_tenant(@guild) do
      @team = Team.create!(name: "Alpha", team_role_id: 1, officer_role_id: 2, review_channel_id: 3)
    end
    sign_in_as users(:member), manageable: [ @guild ]
  end

  def questions = ActsAsTenant.without_tenant { ApplicationQuestion.where(team_id: @team.id).to_a }

  test "the editor offers a description field" do
    get guild_team_path(@guild, @team)

    assert_response :success
    assert_select "input[name=?][maxlength=?]", "application_question[description]",
                  ApplicationQuestion::DESCRIPTION_MAX.to_s
  end

  test "adding a question saves its description" do
    post guild_team_questions_path(@guild, @team), params: { application_question: {
      label: "Raid experience", description: "Which tiers have you cleared, on what difficulty, and with which guild?"
    } }

    assert_redirected_to guild_team_path(@guild, @team)
    assert_equal "Which tiers have you cleared, on what difficulty, and with which guild?", questions.sole.description
  end

  test "editing a question can change and clear its description" do
    question = ActsAsTenant.with_tenant(@guild) do
      @team.application_questions.create!(key: "exp", label: "Raid experience", description: "Old prompt")
    end

    patch guild_team_question_path(@guild, @team, question), params: { application_question: { description: "New prompt" } }
    assert_equal "New prompt", question.reload.description

    patch guild_team_question_path(@guild, @team, question), params: { application_question: { description: "" } }
    assert_predicate question.reload.description, :blank?
  end

  test "an over-long description is refused with the reason" do
    post guild_team_questions_path(@guild, @team), params: { application_question: {
      label: "Raid experience", description: "x" * (ApplicationQuestion::DESCRIPTION_MAX + 1)
    } }

    assert_redirected_to guild_team_path(@guild, @team)
    assert_match(/Description is too long/, flash[:alert])
    assert_empty questions
  end

  test "the editor offers every question style, and an options box" do
    get guild_team_path(@guild, @team)

    assert_select "select[name=?]", "application_question[style]" do
      assert_select "option[value=?]", "choice", text: "Multiple choice"
      assert_select "option[value=?]", "checkboxes", text: "Checkboxes"
      assert_select "option[value=?]", "yes_no", text: "Yes / No"
    end
    assert_select "textarea[name=?]", "application_question[options_text]"
  end

  test "adding a multiple-choice question saves its options" do
    post guild_team_questions_path(@guild, @team), params: { application_question: {
      label: "Main role", style: "choice", options_text: "Tank\r\nHealer\r\nDPS"
    } }

    question = questions.sole
    assert question.choice?
    assert_equal %w[Tank Healer DPS], question.options
  end

  test "a multiple-choice question with too few options is refused with the reason" do
    post guild_team_questions_path(@guild, @team), params: { application_question: {
      label: "Main role", style: "choice", options_text: "Tank"
    } }

    assert_redirected_to guild_team_path(@guild, @team)
    assert_match(/Options need 2–10 for multiple choice/, flash[:alert])
    assert_empty questions
  end

  test "switching a choice question back to text drops its options" do
    question = ActsAsTenant.with_tenant(@guild) do
      @team.application_questions.create!(key: "role", label: "Main role", style: :choice, options_text: "Tank\nHealer")
    end

    patch guild_team_question_path(@guild, @team, question), params: { application_question: { style: "short" } }

    assert question.reload.short?
    assert_empty question.options
  end
end
