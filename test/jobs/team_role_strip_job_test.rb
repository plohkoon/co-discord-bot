require "test_helper"

class TeamRoleStripJobTest < ActiveJob::TestCase
  def guild = @guild ||= Guild.sync_from_discord(id: 1, name: "Test")

  def run_job(result: Memberships::StripRole::Result.new(removed: 2, refused: false))
    calls = []
    stub_singleton_method(Memberships::StripRole, :call, ->(**kwargs) { calls << kwargs and result }) do
      TeamRoleStripJob.perform_now(guild_id: guild.id, role_id: 5, team_name: "Alpha")
    end
    calls
  end

  def guild_log_args
    enqueued_jobs.select { |j| j["job_class"] == "GuildLogJob" }
                 .map { |j| ActiveJob::Arguments.deserialize(j["arguments"]).first }
  end

  test "strips the role with an audit-log reason naming the team" do
    calls = run_job

    assert_equal [ { guild_id: guild.id, role_id: 5, reason: "co-bot: Alpha was deleted" } ], calls
  end

  # Two teams sharing a role: stripping it would pull the survivor's roster.
  test "leaves the role alone while another team still uses it" do
    ActsAsTenant.with_tenant(guild) do
      Team.create!(name: "Bravo", team_role_id: 5, officer_role_id: 6, review_channel_id: 7)
    end

    assert_empty run_job
  end

  test "a refusal is logged so a manager knows the roles are still out there" do
    guild.update!(important_log_channel_id: 4242)

    run_job(result: Memberships::StripRole::Result.new(removed: 0, refused: true))

    log = guild_log_args.sole
    assert_equal [ "Couldn't remove a deleted team's role", :high ], log.values_at(:title, :level)
  end

  test "a clean run logs nothing more — the deletion itself was already logged" do
    guild.update!(important_log_channel_id: 4242)

    run_job

    assert_empty guild_log_args
  end
end
