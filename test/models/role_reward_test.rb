require "test_helper"

class RoleRewardTest < ActiveSupport::TestCase
  setup do
    @guild = Guild.create!(id: 555_000_111_222_333_444, name: "Raid Server")
  end

  def build_reward(**attrs)
    ActsAsTenant.with_tenant(@guild) do
      RoleReward.new({ discord_role_id: 42, kind: "achievement", achievement_name: "Ahead of the Curve: Dimensius" }.merge(attrs))
    end
  end

  test "an achievement rule needs an achievement name" do
    assert_predicate build_reward, :valid?
    reward = build_reward(achievement_name: "  ")
    assert_not reward.valid?
    assert_includes reward.errors[:achievement_name], "can't be blank"
  end

  test "score rules need a positive integer threshold" do
    assert_predicate build_reward(kind: "mythic_plus", threshold: 2500), :valid?
    assert_predicate build_reward(kind: "pvp", threshold: 2400), :valid?

    assert_not build_reward(kind: "mythic_plus", threshold: nil).valid?
    assert_not build_reward(kind: "pvp", threshold: 0).valid?
    assert_not build_reward(kind: "mythic_plus", threshold: -100).valid?
  end

  test "a junk kind fails validation instead of raising" do
    reward = build_reward(kind: "raid_leader")
    assert_not reward.valid?
    assert reward.errors[:kind].any?
  end

  test "pvp bracket type must be a known bracket; blank means any" do
    assert_predicate build_reward(kind: "pvp", threshold: 1, pvp_bracket_type: "shuffle"), :valid?

    any_bracket = build_reward(kind: "pvp", threshold: 1, pvp_bracket_type: "")
    assert_predicate any_bracket, :valid?
    assert_nil any_bracket.pvp_bracket_type

    assert_not build_reward(kind: "pvp", threshold: 1, pvp_bracket_type: "4v4").valid?
  end

  test "each kind clears the other kinds' fields" do
    score = build_reward(kind: "mythic_plus", threshold: 2500,
                         achievement_name: "Stale", pvp_bracket_type: "3v3")
    assert_predicate score, :valid?
    assert_nil score.achievement_name
    assert_nil score.pvp_bracket_type

    achievement = build_reward(threshold: 999, pvp_bracket_type: "3v3")
    assert_predicate achievement, :valid?
    assert_nil achievement.threshold
    assert_nil achievement.pvp_bracket_type
  end

  test "rules are guild-scoped and the role is required" do
    assert_not build_reward(discord_role_id: nil).valid?

    reward = build_reward
    ActsAsTenant.with_tenant(@guild) { reward.save! }
    assert_equal @guild.id, reward.guild_id

    other = Guild.create!(id: 666_000_111_222_333_444, name: "Other")
    assert_empty ActsAsTenant.with_tenant(other) { RoleReward.all.to_a }
  end
end
