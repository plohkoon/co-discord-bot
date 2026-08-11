require "test_helper"

# The character-field toggle: whether the application asks the applicant which
# WoW character they play. Lead-editable like the rest of the team's own
# settings; the model getter self-guards when all five Discord question slots
# are already spent on custom questions.
class TeamCollectCharacterTest < ActionDispatch::IntegrationTest
  setup do
    @guild = Guild.create!(id: 888_000_111_222_333_666, name: "Raid Server")
    ActsAsTenant.with_tenant(@guild) do
      @team = Team.create!(name: "Alpha", team_role_id: 1, officer_role_id: 2, review_channel_id: 3)
      TeamOfficer.create!(team: @team, discord_user_id: users(:member).discord_id,
                          discord_username: users(:member).username)
    end
  end

  test "a team lead can turn the character field off and back on" do
    sign_in_as users(:member), member: [ @guild ]

    patch guild_team_path(@guild, @team), params: { team: { collect_character: "0" } }
    assert_redirected_to guild_team_path(@guild, @team)
    assert_not @team.reload.collect_character?

    patch guild_team_path(@guild, @team), params: { team: { collect_character: "1" } }
    assert @team.reload.collect_character?
  end

  test "plain members can't change it" do
    ActsAsTenant.with_tenant(@guild) { TeamOfficer.delete_all }
    sign_in_as users(:member), member: [ @guild ]

    patch guild_team_path(@guild, @team), params: { team: { collect_character: "0" } }

    assert_redirected_to guild_path(@guild)
    assert @team.reload.collect_character?
  end

  test "the toggle renders in the questions section for a lead" do
    sign_in_as users(:member), member: [ @guild ]

    get guild_team_path(@guild, @team)

    assert_response :success
    assert_select "input[name='team[collect_character]'][type=checkbox]"
  end

  test "five custom questions override the flag until one is removed" do
    ActsAsTenant.with_tenant(@guild) do
      5.times { |i| @team.application_questions.create!(position: i, key: "q#{i}", label: "Q#{i}") }
    end

    assert @team.reload[:collect_character]
    assert_not @team.collect_character?
  end
end
