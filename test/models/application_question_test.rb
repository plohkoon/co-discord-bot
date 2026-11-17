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
