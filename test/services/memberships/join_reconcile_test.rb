require "test_helper"

module Memberships
  # The join-time half of "apply before joining": someone accepted onto teams
  # while outside the server joins, and their deferred team roles get granted.
  class JoinReconcileTest < ActiveSupport::TestCase
    USER_ID = 42

    # Stands in for Discord::BotApi: answers the member lookup and records
    # grants (mutating the member's roles, so a second run sees them held —
    # exactly what Discord would report).
    class FakeApi
      attr_reader :granted

      def initialize(member_roles: [], missing: false, fail_role_ids: [])
        @member_roles = member_roles.map(&:to_s)
        @missing = missing
        @fail_role_ids = fail_role_ids
        @granted = []
      end

      def configured? = true

      def guild_member(_guild_id, _user_id)
        raise Discord::BotApi::NotFound, "404" if @missing

        { "user" => { "id" => USER_ID.to_s }, "roles" => @member_roles.dup }
      end

      def add_member_role(_guild_id, user_id, role_id, reason: nil)
        raise Discord::BotApi::Forbidden, "403" if @fail_role_ids.include?(role_id)

        @member_roles << role_id.to_s
        @granted << [ user_id, role_id ]
      end
    end

    def guild = @guild ||= Guild.sync_from_discord(id: 1, name: "Test")

    def create_team(name, role_id)
      ActsAsTenant.with_tenant(guild) do
        Team.create!(name: name, team_role_id: role_id, officer_role_id: role_id + 100, review_channel_id: 7)
      end
    end

    def create_membership(team, status:)
      ActsAsTenant.with_tenant(guild) do
        TeamMembership.create!(team: team, discord_user_id: USER_ID, discord_username: "recruit", status: status)
      end
    end

    def reconcile(api)
      JoinReconcile.call(guild: guild, discord_user_id: USER_ID, api: api)
    end

    test "grants the team role for an active membership the joiner lacks" do
      team = create_team("Alpha", 5)
      create_membership(team, status: :active)
      api = FakeApi.new

      reconcile(api)

      assert_equal [ [ USER_ID, 5 ] ], api.granted
    end

    test "skips roles the member already holds" do
      team = create_team("Alpha", 5)
      create_membership(team, status: :active)
      api = FakeApi.new(member_roles: [ 5 ])

      reconcile(api)

      assert_empty api.granted
    end

    test "pending and archived memberships are untouched" do
      create_membership(create_team("Alpha", 5), status: :pending)
      create_membership(create_team("Bravo", 6), status: :archived)
      api = FakeApi.new

      reconcile(api)

      assert_empty api.granted
    end

    test "running twice is idempotent — the second pass grants nothing" do
      team = create_team("Alpha", 5)
      create_membership(team, status: :active)
      api = FakeApi.new

      reconcile(api)
      reconcile(api)

      assert_equal [ [ USER_ID, 5 ] ], api.granted
    end

    test "a joiner who already left again is a quiet no-op" do
      create_membership(create_team("Alpha", 5), status: :active)
      api = FakeApi.new(missing: true)

      assert_nothing_raised { reconcile(api) }
      assert_empty api.granted
    end

    test "one team's refusal doesn't block the member's other teams" do
      create_membership(create_team("Alpha", 5), status: :active)
      create_membership(create_team("Bravo", 6), status: :active)
      api = FakeApi.new(fail_role_ids: [ 5 ])

      assert_nothing_raised { reconcile(api) }

      assert_equal [ [ USER_ID, 6 ] ], api.granted
    end
  end
end
