require "test_helper"

module Memberships
  class RoleSyncTest < ActiveSupport::TestCase
    include ActiveJob::TestHelper

    FakeServer = Struct.new(:id, :name)
    FakeMember = Struct.new(:id, :username)
    FakeRole = Struct.new(:id)

    OFFICER_ROLE = 6

    def guild = @guild ||= Guild.sync_from_discord(id: 1, name: "Test")

    def team
      @team ||= ActsAsTenant.with_tenant(guild) do
        Team.create!(name: "Alpha", team_role_id: 5, officer_role_id: OFFICER_ROLE, review_channel_id: 7)
      end
    end

    def reconcile(role_ids)
      team # ensure it exists
      RoleSync.reconcile(server: FakeServer.new(guild.id, guild.name),
                         member: FakeMember.new(11, "alice"),
                         roles: role_ids.map { |id| FakeRole.new(id) })
    end

    def officer_rows = ActsAsTenant.with_tenant(guild) { TeamOfficer.where(team_id: team.id).to_a }

    test "gaining and losing the officer role updates the mirror" do
      reconcile([ OFFICER_ROLE ])
      assert_equal [ 11 ], officer_rows.map(&:discord_user_id)
      assert_equal "alice", officer_rows.first.discord_username

      reconcile([])
      assert_empty officer_rows
    end

    test "officer changes refresh a posted roster; no-op reconciles do not" do
      ActsAsTenant.with_tenant(guild) { team.update!(roster_channel_id: 1, roster_message_id: 2) }

      assert_enqueued_with(job: RosterRefreshJob) { reconcile([ OFFICER_ROLE ]) }

      clear_enqueued_jobs
      reconcile([ OFFICER_ROLE ]) # unchanged — already an officer
      assert_no_enqueued_jobs(only: RosterRefreshJob)
    end

    test "leaving the server clears officer rows and refreshes the roster" do
      ActsAsTenant.with_tenant(guild) { team.update!(roster_channel_id: 1, roster_message_id: 2) }
      reconcile([ OFFICER_ROLE ])
      clear_enqueued_jobs

      assert_enqueued_with(job: RosterRefreshJob) do
        RoleSync.on_leave(server: FakeServer.new(guild.id, guild.name), user_id: 11)
      end
      assert_empty officer_rows
    end
  end
end
