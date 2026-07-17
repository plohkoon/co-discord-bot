require "test_helper"

module Memberships
  class BackfillTest < ActiveSupport::TestCase
    TEAM_ROLE_ID = 500

    # Stands in for Discord::BotApi — yields raw REST member hashes.
    class FakeApi
      def initialize(members) = @members = members

      def each_guild_member(_guild_id, &block) = @members.each(&block)
    end

    def guild = @guild ||= Guild.sync_from_discord(id: 1, name: "Test")

    def team
      @team ||= ActsAsTenant.with_tenant(guild) do
        Team.create!(name: "Alpha", team_role_id: TEAM_ROLE_ID, officer_role_id: 2, review_channel_id: 3)
      end
    end

    def rest_member(id, username, roles:, bot: false)
      user = { "id" => id.to_s, "username" => username }
      user["bot"] = true if bot
      { "user" => user, "roles" => roles.map(&:to_s) }
    end

    def backfill(members)
      ActsAsTenant.with_tenant(guild) { Backfill.call(team: team, api: FakeApi.new(members)) }
    end

    test "activates every human holder of the team role with a manual accepted application" do
      count = backfill([
        rest_member(11, "alice", roles: [ TEAM_ROLE_ID ]),
        rest_member(12, "bob",   roles: [ TEAM_ROLE_ID, 999 ]),
        rest_member(13, "carol", roles: [ 999 ]),               # different role
        rest_member(14, "beep",  roles: [ TEAM_ROLE_ID ], bot: true)
      ])

      assert_equal 2, count
      ActsAsTenant.with_tenant(guild) do
        assert_equal %w[11 12], TeamMembership.active.pluck(:discord_user_id).map(&:to_s).sort
        application = TeamMembership.find_by(discord_user_id: 11).team_applications.accepted.sole
        assert_equal "manual", application.source
      end
    end

    test "is idempotent and reactivates archived members" do
      members = [ rest_member(11, "alice", roles: [ TEAM_ROLE_ID ]) ]

      backfill(members)
      ActsAsTenant.with_tenant(guild) { Archive.for(team: team, discord_user_id: 11) }

      assert_equal 1, backfill(members)
      ActsAsTenant.with_tenant(guild) do
        assert_equal 1, TeamMembership.where(discord_user_id: 11).count
        assert TeamMembership.find_by(discord_user_id: 11).active?
      end
    end

    test "returns 0 when nobody holds the role" do
      assert_equal 0, backfill([ rest_member(11, "alice", roles: [ 999 ]) ])
      assert_equal 0, backfill([])
    end

    test "seeds and prunes the officers mirror from the officer role" do
      officer_role = team.officer_role_id
      backfill([ rest_member(21, "olive", roles: [ officer_role ]),
                 rest_member(22, "omar",  roles: [ officer_role ]) ])

      ActsAsTenant.with_tenant(guild) do
        assert_equal [ 21, 22 ], TeamOfficer.where(team_id: team.id).order(:discord_user_id).pluck(:discord_user_id)
      end

      backfill([ rest_member(21, "olive", roles: [ officer_role ]) ]) # omar lost the role offline
      ActsAsTenant.with_tenant(guild) do
        assert_equal [ 21 ], TeamOfficer.where(team_id: team.id).pluck(:discord_user_id)
      end
    end
  end
end
