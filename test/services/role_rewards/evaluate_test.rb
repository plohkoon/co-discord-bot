require "test_helper"

module RoleRewards
  class EvaluateTest < ActiveSupport::TestCase
    # Records role calls; raises a preset error per discord user id.
    class FakeApi
      attr_reader :added, :removed
      attr_accessor :add_errors, :remove_errors

      def initialize
        @added = []
        @removed = []
        @add_errors = {}
        @remove_errors = {}
      end

      def configured? = true

      def add_member_role(guild_id, user_id, role_id, reason: nil)
        error = @add_errors[user_id.to_i]
        raise error if error

        @added << [ guild_id, user_id.to_i, role_id ]
      end

      def remove_member_role(guild_id, user_id, role_id, reason: nil)
        error = @remove_errors[user_id.to_i]
        raise error if error

        @removed << [ guild_id, user_id.to_i, role_id ]
      end
    end

    ROLE = 900_000_000_000_000_001

    setup do
      @guild = Guild.create!(id: 555_000_111_222_333_444, name: "Raid Server")
      @api = FakeApi.new
      @next_discord_id = 700_000_000_000_000_000
      @next_blizzard_id = 1
    end

    def create_user
      User.create!(discord_id: (@next_discord_id += 1), username: "u#{@next_discord_id}")
    end

    def create_character(user, **attrs)
      WowCharacter.create!({ user: user, blizzard_id: (@next_blizzard_id += 1),
                             name: "Char#{@next_blizzard_id}", realm: "Thrall", realm_slug: "thrall",
                             region: "us", claimed_at: Time.current }.merge(attrs))
    end

    def create_reward(**attrs)
      ActsAsTenant.with_tenant(@guild) do
        RoleReward.create!({ discord_role_id: ROLE }.merge(attrs))
      end
    end

    def grants(reward) = ActsAsTenant.without_tenant { reward.role_reward_grants.reload.pluck(:discord_user_id) }

    def sweep = Evaluate.call(guild: @guild, api: @api)

    test "achievement rules match the exact stored name, any owned character" do
      earned, other_achievement, no_data = create_user, create_user, create_user
      create_character(earned).wow_character_achievements.create!(
        blizzard_id: 1, name: "Ahead of the Curve: Dimensius", category: "aotc", completed_at: Time.current)
      create_character(other_achievement).wow_character_achievements.create!(
        blizzard_id: 2, name: "Cutting Edge: Dimensius", category: "cutting_edge", completed_at: Time.current)
      create_character(no_data)

      reward = create_reward(kind: "achievement", achievement_name: "Ahead of the Curve: Dimensius")
      sweep

      assert_equal [ [ @guild.id, earned.discord_id, ROLE ] ], @api.added
      assert_equal [ earned.discord_id ], grants(reward)
    end

    test "mythic+ rules honor the zero-means-absent rule and the Blizzard fallback" do
      raider_io = create_user   # Raider.io score qualifies
      fallback  = create_user   # Raider.io empty, Blizzard rating qualifies
      low       = create_user   # real score below the bar
      zeroes    = create_user   # 0 everywhere = no keys this season
      create_character(raider_io, raider_io_score: 2600)
      create_character(fallback, raider_io_score: 0, mythic_rating: 2550)
      create_character(low, raider_io_score: 2400, mythic_rating: 100)
      create_character(zeroes, raider_io_score: 0, mythic_rating: 0)

      create_reward(kind: "mythic_plus", threshold: 2500)
      sweep

      assert_equal [ raider_io.discord_id, fallback.discord_id ].sort, @api.added.map { |_, id, _| id }.sort
    end

    test "pvp rules count any current-season bracket, or just the configured one" do
      WowPvpSeason.create!(blizzard_id: 41, current: true)
      shuffler, twos, past_season = create_user, create_user, create_user
      create_character(shuffler).wow_character_pvp_ratings.create!(
        bracket: "shuffle-mage-frost", bracket_type: "shuffle", spec_slug: "mage-frost",
        season_id: 41, rating: 2450, fetched_at: Time.current)
      create_character(twos).wow_character_pvp_ratings.create!(
        bracket: "2v2", bracket_type: "2v2", season_id: 41, rating: 2500, fetched_at: Time.current)
      create_character(past_season).wow_character_pvp_ratings.create!(
        bracket: "3v3", bracket_type: "3v3", season_id: 40, rating: 3000, fetched_at: Time.current)

      any_bracket = create_reward(kind: "pvp", threshold: 2400)
      sweep
      assert_equal [ shuffler.discord_id, twos.discord_id ].sort, @api.added.map { |_, id, _| id }.sort

      ActsAsTenant.with_tenant(@guild) { any_bracket.destroy }
      @api = FakeApi.new
      create_reward(kind: "pvp", threshold: 2400, pvp_bracket_type: "shuffle")
      sweep
      assert_equal [ shuffler.discord_id ], @api.added.map { |_, id, _| id }
    end

    test "a pvp rule with no season reference data touches nothing" do
      user = create_user
      create_character(user).wow_character_pvp_ratings.create!(
        bracket: "2v2", bracket_type: "2v2", season_id: 41, rating: 3000, fetched_at: Time.current)
      reward = create_reward(kind: "pvp", threshold: 1, auto_revoke: true)
      reward.role_reward_grants.create!(discord_user_id: 12345, granted_at: Time.current)

      sweep

      assert_empty @api.added
      assert_empty @api.removed
      assert_equal [ 12345 ], grants(reward)
    end

    test "already-granted users cost no REST call" do
      user = create_user
      create_character(user, raider_io_score: 2600)
      reward = create_reward(kind: "mythic_plus", threshold: 2500)
      reward.role_reward_grants.create!(discord_user_id: user.discord_id, granted_at: 1.day.ago)

      sweep

      assert_empty @api.added
    end

    test "a 404 on grant (not in the guild) is skipped, not recorded" do
      absent, present = create_user, create_user
      create_character(absent, raider_io_score: 2600)
      create_character(present, raider_io_score: 2700)
      @api.add_errors[absent.discord_id] = Discord::BotApi::NotFound.new("unknown member")

      reward = create_reward(kind: "mythic_plus", threshold: 2500)
      sweep

      assert_equal [ present.discord_id ], grants(reward)
    end

    test "a Forbidden (hierarchy/permissions) halts the rule without recording grants" do
      user = create_user
      create_character(user, raider_io_score: 2600)
      @api.add_errors[user.discord_id] = Discord::BotApi::Forbidden.new("missing permissions")

      reward = create_reward(kind: "mythic_plus", threshold: 2500)
      sweep

      assert_empty grants(reward)
    end

    test "auto_revoke strips users whose score dropped or vanished and deletes the grant row" do
      dropped, still_good = create_user, create_user
      create_character(dropped, raider_io_score: 0, mythic_rating: 0) # season reset
      create_character(still_good, raider_io_score: 2600)
      reward = create_reward(kind: "mythic_plus", threshold: 2500, auto_revoke: true)
      [ dropped, still_good ].each do |user|
        reward.role_reward_grants.create!(discord_user_id: user.discord_id, granted_at: 1.week.ago)
      end

      sweep

      assert_equal [ [ @guild.id, dropped.discord_id, ROLE ] ], @api.removed
      assert_equal [ still_good.discord_id ], grants(reward)
    end

    test "without auto_revoke a lapsed score is left alone" do
      lapsed = create_user
      create_character(lapsed, raider_io_score: 0, mythic_rating: 0)
      reward = create_reward(kind: "mythic_plus", threshold: 2500)
      reward.role_reward_grants.create!(discord_user_id: lapsed.discord_id, granted_at: 1.week.ago)

      sweep

      assert_empty @api.removed
      assert_equal [ lapsed.discord_id ], grants(reward)
    end

    test "a 404 on removal still clears the grant row" do
      gone = create_user
      create_character(gone, raider_io_score: 0, mythic_rating: 0)
      @api.remove_errors[gone.discord_id] = Discord::BotApi::NotFound.new("unknown member")
      reward = create_reward(kind: "mythic_plus", threshold: 2500, auto_revoke: true)
      reward.role_reward_grants.create!(discord_user_id: gone.discord_id, granted_at: 1.week.ago)

      sweep

      assert_empty grants(reward)
    end

    test "a transient error on removal keeps the grant row for the next sweep" do
      flaky = create_user
      create_character(flaky, raider_io_score: 0, mythic_rating: 0)
      @api.remove_errors[flaky.discord_id] = Discord::BotApi::Error.new("HTTP 500")
      reward = create_reward(kind: "mythic_plus", threshold: 2500, auto_revoke: true)
      reward.role_reward_grants.create!(discord_user_id: flaky.discord_id, granted_at: 1.week.ago)

      sweep

      assert_equal [ flaky.discord_id ], grants(reward)
    end

    test "auto_revoke never strips a still-earned achievement" do
      earned = create_user
      create_character(earned).wow_character_achievements.create!(
        blizzard_id: 1, name: "Cutting Edge: Dimensius", category: "cutting_edge", completed_at: 1.year.ago)
      reward = create_reward(kind: "achievement", achievement_name: "Cutting Edge: Dimensius", auto_revoke: true)
      reward.role_reward_grants.create!(discord_user_id: earned.discord_id, granted_at: 1.week.ago)

      sweep

      assert_empty @api.removed
      assert_equal [ earned.discord_id ], grants(reward)
    end

    test "auto_revoke strips an achievement rule when the character data is gone" do
      vanished = create_user
      reward = create_reward(kind: "achievement", achievement_name: "Cutting Edge: Dimensius", auto_revoke: true)
      reward.role_reward_grants.create!(discord_user_id: vanished.discord_id, granted_at: 1.week.ago)

      sweep

      assert_equal [ [ @guild.id, vanished.discord_id, ROLE ] ], @api.removed
      assert_empty grants(reward)
    end
  end
end
