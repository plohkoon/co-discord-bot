require "test_helper"

module Memberships
  class ActivateTest < ActiveSupport::TestCase
    def guild = @guild ||= Guild.sync_from_discord(id: 1, name: "Test")

    def team
      @team ||= ActsAsTenant.with_tenant(guild) do
        Team.create!(name: "Alpha", team_role_id: 5, officer_role_id: 6, review_channel_id: 7)
      end
    end

    def activate
      ActsAsTenant.with_tenant(guild) do
        Activate.call(team: team, discord_user_id: 11, username: "alice")
      end
    end

    def build_pending_membership
      ActsAsTenant.with_tenant(guild) do
        membership = TeamMembership.create!(team: team, discord_user_id: 11, discord_username: "alice", status: :pending)
        application = membership.team_applications.create!(team: team, discord_user_id: 11, discord_username: "alice")
        [ membership, application ]
      end
    end

    test "a manual grant with no application history leaves a synthetic accepted record" do
      membership = activate

      assert membership.active?
      application = membership.team_applications.sole
      assert application.accepted?
      assert application.manual?
    end

    test "a manual grant while an application is pending accepts it — no synthetic duplicate" do
      membership, application = build_pending_membership

      activate

      assert membership.reload.active?
      application.reload
      assert application.accepted?
      assert application.applied? # the real application is the record
      assert_nil application.decided_by_discord_id # system decision, like auto-reject
      assert_equal [ application.id ], membership.team_applications.ids
    end

    test "an already-active membership still gets its dangling pending application resolved" do
      membership, application = build_pending_membership
      membership.update!(status: :active, joined_at: Time.current)

      activate

      assert application.reload.accepted?
    end
  end
end
