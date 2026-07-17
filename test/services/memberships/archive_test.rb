require "test_helper"

module Memberships
  class ArchiveTest < ActiveSupport::TestCase
    def guild = @guild ||= Guild.sync_from_discord(id: 1, name: "Test")

    def team
      @team ||= ActsAsTenant.with_tenant(guild) do
        Team.create!(name: "Alpha", team_role_id: 5, officer_role_id: 6, review_channel_id: 7)
      end
    end

    def build_pending_membership
      ActsAsTenant.with_tenant(guild) do
        membership = TeamMembership.create!(team: team, discord_user_id: 11, discord_username: "alice", status: :pending)
        application = membership.team_applications.create!(team: team, discord_user_id: 11, discord_username: "alice")
        [ membership, application ]
      end
    end

    test "archiving system-rejects a pending application" do
      membership, application = build_pending_membership

      ActsAsTenant.with_tenant(guild) { Archive.call(membership) }

      assert membership.reload.archived?
      application.reload
      assert application.rejected?
      assert_nil application.decided_by_discord_id # system decision, like auto-reject
      assert_not_nil application.decided_at
    end

    test "an already-archived membership still gets its dangling pending application resolved" do
      membership, application = build_pending_membership
      membership.update!(status: :archived, left_at: Time.current)

      ActsAsTenant.with_tenant(guild) { Archive.call(membership) }

      assert application.reload.rejected?
    end

    test ".for leaves a pending applicant alone — lacking the role is their expected state" do
      membership, application = build_pending_membership

      ActsAsTenant.with_tenant(guild) { Archive.for(team: team, discord_user_id: 11) }

      assert membership.reload.pending?
      assert application.reload.pending?
    end

    test "archiving leaves decided applications alone" do
      membership, application = build_pending_membership
      ActsAsTenant.with_tenant(guild) do
        Applications::Decide.call(application: application, decision: :reject, decided_by_discord_id: 99)
        Archive.call(membership)
      end

      application.reload
      assert application.rejected?
      assert_equal 99, application.decided_by_discord_id # the officer's decision stands
    end
  end
end
