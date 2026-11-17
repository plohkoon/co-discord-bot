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
end
