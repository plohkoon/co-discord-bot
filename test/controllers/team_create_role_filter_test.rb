require "test_helper"

# The New-team form's TEAM role picker must never offer a role carrying a
# dangerous Discord permission (the bot grants that role), and a hand-crafted
# POST that names one anyway must be rejected — the write-side check validates
# against the same filtered list the picker is built from.
#
# The OFFICER role picker is deliberately not filtered that way: the bot never
# grants the officer role, only reads and pings it, and lead roles routinely
# carry Kick/Manage Roles — filtering hid every one of them.
class TeamCreateRoleFilterTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    @guild = Guild.create!(id: 777_000_111_222_333_555, name: "Raid Server")
  end

  ROLES = [
    { "name" => "Raider",   "id" => "111", "position" => 5, "managed" => false, "permissions" => "0" },
    { "name" => "Officers", "id" => "222", "position" => 4, "managed" => false, "permissions" => "2048" }, # Send Messages
    { "name" => "Admins",   "id" => "999", "position" => 8, "managed" => false, "permissions" => "8" }, # Administrator
    { "name" => "Raid Lead", "id" => "333", "position" => 6, "managed" => false, "permissions" => "268435458" }, # Manage Roles + Kick
    { "name" => "co-bot",   "id" => "444", "position" => 9, "managed" => true,  "permissions" => "268435456" } # bot-managed
  ].freeze

  CHANNELS = [ { "name" => "review", "id" => "700", "position" => 1, "type" => 0 } ].freeze

  # configured? is true so load_discord_options actually fetches the roles.
  class FakeApi
    def initialize(roles:, channels:)
      @roles = roles
      @channels = channels
    end

    def configured? = true
    def guild_roles(_id) = @roles
    def guild_channels(_id) = @channels
  end

  def with_fake_api(&block)
    api = FakeApi.new(roles: ROLES, channels: CHANNELS)
    stub_singleton_method(Discord::BotApi, :new, api, &block)
  end

  def teams = ActsAsTenant.with_tenant(@guild) { Team.all.to_a }

  test "the team-role picker hides roles carrying a dangerous permission" do
    sign_in_as users(:member), manageable: [ @guild ]

    with_fake_api { get new_guild_team_path(@guild) }

    assert_response :success
    assert_select "select[name=?]", "team[team_role_id]" do
      assert_select "option[value=?]", "111" # plain role offered
      assert_select "option[value=?]", "222" # harmless-permission role offered
      assert_select "option[value=?]", "999", count: 0 # Administrator role filtered out
      assert_select "option[value=?]", "333", count: 0 # moderator-bit lead role filtered out
      assert_select "option[value=?]", "444", count: 0 # bot-managed role filtered out
    end
  end

  test "the officer-role picker offers lead roles with moderator permissions" do
    sign_in_as users(:member), manageable: [ @guild ]

    with_fake_api { get new_guild_team_path(@guild) }

    assert_response :success
    assert_select "select[name=?]", "team[officer_role_id]" do
      assert_select "option[value=?]", "222"
      assert_select "option[value=?]", "333" # Manage Roles + Kick — a typical lead role
      assert_select "option[value=?]", "999" # never granted by the bot, so safe to offer
      assert_select "option[value=?]", "444", count: 0 # bot-managed roles still excluded
      assert_select "option[value=?]", @guild.id.to_s, count: 0 # @everyone still excluded
    end
  end

  test "a plain role creates the team" do
    sign_in_as users(:member), manageable: [ @guild ]

    with_fake_api do
      post guild_teams_path(@guild), params: { team: {
        name: "Alpha", team_role_id: "111", officer_role_id: "222", review_channel_id: "700"
      } }
    end

    team = teams.sole
    assert_equal 111, team.team_role_id
    assert_equal 222, team.officer_role_id
  end

  test "a crafted POST naming an Administrator role is rejected" do
    sign_in_as users(:member), manageable: [ @guild ]

    with_fake_api do
      post guild_teams_path(@guild), params: { team: {
        name: "Sneaky", team_role_id: "999", officer_role_id: "222", review_channel_id: "700"
      } }
    end

    assert_response :unprocessable_entity
    assert_match(/from the lists/, flash[:alert])
    assert_empty teams
  end

  test "a lead role with moderator permissions can be the officer role" do
    sign_in_as users(:member), manageable: [ @guild ]

    with_fake_api do
      post guild_teams_path(@guild), params: { team: {
        name: "Raiders", team_role_id: "111", officer_role_id: "333", review_channel_id: "700"
      } }
    end

    assert_equal 333, teams.sole.officer_role_id
  end

  test "a crafted POST naming a bot-managed officer role is rejected" do
    sign_in_as users(:member), manageable: [ @guild ]

    with_fake_api do
      post guild_teams_path(@guild), params: { team: {
        name: "Sneaky", team_role_id: "111", officer_role_id: "444", review_channel_id: "700"
      } }
    end

    assert_response :unprocessable_entity
    assert_match(/from the lists/, flash[:alert])
    assert_empty teams
  end
end
