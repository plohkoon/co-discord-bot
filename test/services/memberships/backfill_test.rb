require "test_helper"

module Memberships
  class BackfillTest < ActiveSupport::TestCase
    TEAM_ROLE_ID = 500

    FakeMember = Struct.new(:id, :username, :bot) do
      def bot_account? = bot
    end

    FakeRole = Struct.new(:id, :members)

    class FakeServer
      def initialize(roles) = @roles = roles
      def role(id) = @roles.find { |r| r.id == id }
    end

    def guild = @guild ||= Guild.sync_from_discord(id: 1, name: "Test")

    def team
      @team ||= ActsAsTenant.with_tenant(guild) do
        Team.create!(name: "Alpha", team_role_id: TEAM_ROLE_ID, officer_role_id: 2, review_channel_id: 3)
      end
    end

    def backfill(server)
      ActsAsTenant.with_tenant(guild) { Backfill.call(team: team, server: server) }
    end

    test "activates every human holder of the team role with a manual accepted application" do
      server = FakeServer.new([ FakeRole.new(TEAM_ROLE_ID, [
        FakeMember.new(11, "alice", false),
        FakeMember.new(12, "bob", false),
        FakeMember.new(13, "beep", true) # bot — skipped
      ]) ])

      assert_equal 2, backfill(server)

      ActsAsTenant.with_tenant(guild) do
        assert_equal %w[11 12], TeamMembership.active.pluck(:discord_user_id).map(&:to_s).sort
        membership = TeamMembership.find_by(discord_user_id: 11)
        application = membership.team_applications.accepted.sole
        assert_equal "manual", application.source
        assert_not TeamMembership.exists?(discord_user_id: 13)
      end
    end

    test "is idempotent and reactivates archived members" do
      member = FakeMember.new(11, "alice", false)
      server = FakeServer.new([ FakeRole.new(TEAM_ROLE_ID, [ member ]) ])

      backfill(server)
      ActsAsTenant.with_tenant(guild) do
        Archive.for(team: team, discord_user_id: 11)
      end

      assert_equal 1, backfill(server)
      ActsAsTenant.with_tenant(guild) do
        assert_equal 1, TeamMembership.where(discord_user_id: 11).count
        assert TeamMembership.find_by(discord_user_id: 11).active?
      end
    end

    test "returns 0 when the role no longer exists" do
      assert_equal 0, backfill(FakeServer.new([]))
      assert_equal 0, backfill(nil)
    end
  end
end
