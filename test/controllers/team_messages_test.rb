require "test_helper"

# The automated DM templates (apply/absence) are part of the officer toolkit —
# a team lead edits them, not just a Manage-Server admin. Saving them alone
# doesn't reflow the roster (they aren't shown there).
class TeamMessagesTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    @guild = Guild.create!(id: 888_000_111_222_333_444, name: "Raid Server")
    ActsAsTenant.with_tenant(@guild) do
      @category = TeamCategory.create!(name: "PvE Teams")
      @team = Team.create!(name: "Alpha", team_role_id: 1, officer_role_id: 2, review_channel_id: 3,
                           team_category: @category)
      TeamOfficer.create!(team: @team, discord_user_id: users(:member).discord_id,
                          discord_username: users(:member).username)
    end
  end

  def refresh_jobs = enqueued_jobs.count { |job| job["job_class"] == "RosterRefreshJob" }

  test "a team lead can save the DM templates without reflowing the roster" do
    sign_in_as users(:member), member: [ @guild ]

    assert_no_difference -> { refresh_jobs } do
      patch guild_team_path(@guild, @team),
            params: { team: { apply_response: "Welcome {user} to {team}!", absence_response: "Noted, {user}." } }
    end

    assert_redirected_to guild_team_path(@guild, @team)
    @team.reload
    assert_equal "Welcome {user} to {team}!", @team.apply_response
    assert_equal "Noted, {user}.", @team.absence_response
    assert_equal @category.id, @team.team_category_id # a message-only save leaves the category intact
  end

  test "plain members can't save the DM templates" do
    ActsAsTenant.with_tenant(@guild) { TeamOfficer.delete_all }
    sign_in_as users(:member), member: [ @guild ]

    patch guild_team_path(@guild, @team), params: { team: { apply_response: "sneaky" } }

    assert_redirected_to guild_path(@guild)
    assert_nil @team.reload.apply_response
  end
end
