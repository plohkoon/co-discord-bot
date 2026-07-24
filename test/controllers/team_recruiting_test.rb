require "test_helper"

# The recruiting toggle + its "not recruiting" roster message are part of the
# officer toolkit — a team lead sets them, not just a Manage-Server admin.
# Toggling reflows the posted roster (the Apply button appears/disappears).
class TeamRecruitingTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    @guild = Guild.create!(id: 888_000_111_222_333_555, name: "Raid Server")
    ActsAsTenant.with_tenant(@guild) do
      @team = Team.create!(name: "Alpha", team_role_id: 1, officer_role_id: 2, review_channel_id: 3)
      TeamOfficer.create!(team: @team, discord_user_id: users(:member).discord_id,
                          discord_username: users(:member).username)
    end
  end

  def refresh_jobs = enqueued_jobs.count { |job| job["job_class"] == "RosterRefreshJob" }

  test "a team lead can close recruiting, and it reflows the roster" do
    sign_in_as users(:member), member: [ @guild ]

    assert_difference -> { refresh_jobs }, 1 do
      patch guild_team_path(@guild, @team),
            params: { team: { recruiting: "0", closed_message: "{team} is full." } }
    end

    assert_redirected_to guild_team_path(@guild, @team)
    @team.reload
    assert_not @team.recruiting?
    assert_equal "{team} is full.", @team.closed_message
  end

  test "plain members can't change recruiting" do
    ActsAsTenant.with_tenant(@guild) { TeamOfficer.delete_all }
    sign_in_as users(:member), member: [ @guild ]

    patch guild_team_path(@guild, @team), params: { team: { recruiting: "0" } }

    assert_redirected_to guild_path(@guild)
    assert @team.reload.recruiting?
  end

  test "a recruiting-only save leaves the team's category, type, and roster fields intact" do
    category, type = ActsAsTenant.with_tenant(@guild) do
      [ TeamCategory.create!(name: "PvE"), TeamType.create!(name: "Heroic Team") ]
    end
    ActsAsTenant.with_tenant(@guild) do
      @team.update!(team_category: category, team_type: type, progression: "7/9 H")
    end
    sign_in_as users(:member), member: [ @guild ]

    patch guild_team_path(@guild, @team), params: { team: { recruiting: "0", closed_message: "Full." } }

    @team.reload
    assert_not @team.recruiting?
    assert_equal category.id, @team.team_category_id # not wiped by the recruiting-only form
    assert_equal type.id, @team.team_type_id
    assert_equal "7/9 H", @team.progression
  end
end
