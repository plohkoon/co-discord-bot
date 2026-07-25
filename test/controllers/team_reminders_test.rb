require "test_helper"

# Reminder cadence is part of the officer toolkit — a team lead tunes it, not
# just a Manage-Server admin. None of it shows in the /team roster directory,
# so saving it must NOT reflow the posted roster.
class TeamRemindersTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    @guild = Guild.create!(id: 888_000_111_222_444_777, name: "Raid Server")
    ActsAsTenant.with_tenant(@guild) do
      @team = Team.create!(name: "Alpha", team_role_id: 1, officer_role_id: 2, review_channel_id: 3)
      TeamOfficer.create!(team: @team, discord_user_id: users(:member).discord_id,
                          discord_username: users(:member).username)
    end
  end

  def refresh_jobs = enqueued_jobs.count { |job| job["job_class"] == "RosterRefreshJob" }

  test "a team lead can tune the digest without reflowing the roster" do
    sign_in_as users(:member), member: [ @guild ]

    assert_no_difference -> { refresh_jobs } do
      patch guild_team_path(@guild, @team),
            params: { team: { review_digest: "1", review_digest_after_days: "3", remind_ping: "0" } }
    end

    assert_redirected_to guild_team_path(@guild, @team)
    @team.reload
    assert @team.review_digest?
    assert_equal 3, @team.review_digest_after_days
    assert_not @team.remind_ping?
  end

  test "an out-of-range threshold is rejected rather than saved" do
    sign_in_as users(:member), member: [ @guild ]

    patch guild_team_path(@guild, @team), params: { team: { review_digest_after_days: "99" } }

    assert_match(/Review digest after days/i, flash[:alert])
    assert_equal 1, @team.reload.review_digest_after_days
  end

  test "a digest-only save leaves the team's roster details intact" do
    ActsAsTenant.with_tenant(@guild) { @team.update!(progression: "7/9 H", apply_response: "Thanks!") }
    sign_in_as users(:member), member: [ @guild ]

    patch guild_team_path(@guild, @team), params: { team: { remind_ping: "0" } }

    @team.reload
    assert_not @team.remind_ping?
    assert_equal "7/9 H", @team.progression
    assert_equal "Thanks!", @team.apply_response
  end

  test "plain members can't change the digest settings" do
    ActsAsTenant.with_tenant(@guild) { TeamOfficer.delete_all }
    sign_in_as users(:member), member: [ @guild ]

    patch guild_team_path(@guild, @team), params: { team: { remind_ping: "0" } }

    assert_redirected_to guild_path(@guild)
    assert @team.reload.remind_ping?
  end
end
