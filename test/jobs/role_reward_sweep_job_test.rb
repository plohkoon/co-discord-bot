require "test_helper"

class RoleRewardSweepJobTest < ActiveSupport::TestCase
  class FakeApi
    attr_reader :added

    def initialize(configured: true)
      @configured = configured
      @added = []
    end

    def configured? = @configured

    def add_member_role(guild_id, user_id, role_id, reason: nil) = @added << [ guild_id, user_id.to_i, role_id ]

    def remove_member_role(*, **) = nil
  end

  setup do
    @guild = Guild.create!(id: 555_000_111_222_333_444, name: "Raid Server")
    @user = User.create!(discord_id: 700_000_000_000_000_001, username: "raider")
    WowCharacter.create!(user: @user, blizzard_id: 1, name: "Char", realm: "Thrall", realm_slug: "thrall",
                         region: "us", claimed_at: Time.current, raider_io_score: 2600)
    ActsAsTenant.with_tenant(@guild) do
      RoleReward.create!(kind: "mythic_plus", threshold: 2500, discord_role_id: 42)
    end
  end

  test "sweeps every installed guild with rules" do
    api = FakeApi.new
    RoleRewardSweepJob.perform_now(api: api)

    assert_equal [ [ @guild.id, @user.discord_id, 42 ] ], api.added
  end

  test "skips guilds the bot was removed from" do
    @guild.update!(removed_at: Time.current)
    api = FakeApi.new
    RoleRewardSweepJob.perform_now(api: api)

    assert_empty api.added
  end

  test "a guild_id narrows the sweep to that guild" do
    other = Guild.create!(id: 666_000_111_222_333_444, name: "Other")
    ActsAsTenant.with_tenant(other) do
      RoleReward.create!(kind: "mythic_plus", threshold: 2500, discord_role_id: 43)
    end

    api = FakeApi.new
    RoleRewardSweepJob.perform_now(guild_id: other.id, api: api)

    assert_equal [ [ other.id, @user.discord_id, 43 ] ], api.added
  end

  test "no-ops without a bot token" do
    api = FakeApi.new(configured: false)
    RoleRewardSweepJob.perform_now(api: api)

    assert_empty api.added
  end
end
