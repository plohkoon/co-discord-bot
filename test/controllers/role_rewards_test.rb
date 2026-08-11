require "test_helper"

# WoW role rewards on the guild page: Manage Server only, the granted role
# must come from the server's real role list, and adding a rule kicks off an
# immediate evaluation sweep.
class RoleRewardsTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    @guild = Guild.create!(id: 555_000_111_222_333_444, name: "Raid Server")
  end

  # Stands in for Discord::BotApi. configured? is false so the show page's
  # GuildHealth check short-circuits without any real HTTP.
  class FakeApi
    def initialize(roles) = @roles = roles
    def configured? = false
    def guild_roles(_id) = @roles
    def guild_channels(_id) = []
  end

  ROLES = [
    { "name" => "Cutting Edge", "id" => "111", "position" => 5, "managed" => false },
    { "name" => "Gladiator",    "id" => "222", "position" => 4, "managed" => false },
    { "name" => "co-bot",       "id" => "333", "position" => 9, "managed" => true } # bot-managed, filtered
  ].freeze

  def with_fake_api(roles: ROLES, &block)
    stub_singleton_method(Discord::BotApi, :new, FakeApi.new(roles), &block)
  end

  def rewards = ActsAsTenant.with_tenant(@guild) { RoleReward.all.to_a }

  def sweep_jobs = enqueued_jobs.count { |job| job["job_class"] == "RoleRewardSweepJob" }

  test "a manager can add a rule; an immediate sweep is enqueued" do
    sign_in_as users(:member), manageable: [ @guild ]

    assert_difference -> { sweep_jobs } do
      with_fake_api do
        post guild_role_rewards_path(@guild), params: { role_reward: {
          kind: "mythic_plus", threshold: "2500", discord_role_id: "111", auto_revoke: "1"
        } }
      end
    end

    assert_redirected_to guild_path(@guild)
    reward = rewards.sole
    assert_equal "mythic_plus", reward.kind
    assert_equal 2500, reward.threshold
    assert_equal 111, reward.discord_role_id
    assert reward.auto_revoke?
  end

  test "a role id outside the server's role list is rejected" do
    sign_in_as users(:member), manageable: [ @guild ]

    [ "999", "333" ].each do |role_id| # unknown, and bot-managed
      with_fake_api do
        post guild_role_rewards_path(@guild), params: { role_reward: {
          kind: "achievement", achievement_name: "Cutting Edge: Dimensius", discord_role_id: role_id
        } }
      end
      assert_match(/from the list/, flash[:alert])
    end
    assert_empty rewards
  end

  test "an invalid rule redirects with the errors and enqueues nothing" do
    sign_in_as users(:member), manageable: [ @guild ]

    assert_no_difference -> { sweep_jobs } do
      with_fake_api do
        post guild_role_rewards_path(@guild), params: { role_reward: {
          kind: "achievement", achievement_name: "", discord_role_id: "111"
        } }
      end
    end

    assert_match(/Achievement name/i, flash[:alert])
    assert_empty rewards
  end

  test "a manager can delete a rule; its grant records go with it" do
    reward = ActsAsTenant.with_tenant(@guild) do
      RoleReward.create!(kind: "achievement", achievement_name: "Cutting Edge: Dimensius", discord_role_id: 111)
    end
    reward.role_reward_grants.create!(discord_user_id: 42, granted_at: Time.current)
    sign_in_as users(:member), manageable: [ @guild ]

    with_fake_api { delete guild_role_reward_path(@guild, reward) }

    assert_redirected_to guild_path(@guild)
    assert_empty rewards
    assert_equal 0, RoleRewardGrant.count
  end

  test "a plain member can neither add nor delete rules" do
    reward = ActsAsTenant.with_tenant(@guild) do
      RoleReward.create!(kind: "achievement", achievement_name: "Cutting Edge: Dimensius", discord_role_id: 111)
    end
    sign_in_as users(:member), member: [ @guild ]

    with_fake_api do
      post guild_role_rewards_path(@guild), params: { role_reward: {
        kind: "mythic_plus", threshold: "1", discord_role_id: "111"
      } }
      delete guild_role_reward_path(@guild, reward)
    end

    assert_equal [ reward.id ], rewards.map(&:id)
  end

  test "managers see the section; members don't" do
    sign_in_as users(:member), manageable: [ @guild ]
    with_fake_api { get guild_path(@guild) }
    assert_response :success
    assert_select "h2", text: /WoW role rewards/
    assert_select "select[name='role_reward[discord_role_id]'] option[value=?]", "111"
    assert_select "select[name='role_reward[discord_role_id]'] option[value=?]", "333", count: 0 # managed filtered

    sign_in_as users(:member), member: [ @guild ]
    with_fake_api { get guild_path(@guild) }
    assert_response :success
    assert_select "h2", text: /WoW role rewards/, count: 0
  end
end
