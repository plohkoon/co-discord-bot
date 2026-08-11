require "test_helper"

# The New-team form's role pickers (team role + officer role) must never offer
# a role carrying a dangerous Discord permission, and a hand-crafted POST that
# names one anyway must be rejected — the write-side check validates against
# the same filtered list the picker is built from.
class TeamCreateRoleFilterTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    @guild = Guild.create!(id: 777_000_111_222_333_555, name: "Raid Server")
  end

  ROLES = [
    { "name" => "Raider",   "id" => "111", "position" => 5, "managed" => false, "permissions" => "0" },
    { "name" => "Officers", "id" => "222", "position" => 4, "managed" => false, "permissions" => "2048" }, # Send Messages
    { "name" => "Admins",   "id" => "999", "position" => 8, "managed" => false, "permissions" => "8" } # Administrator
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

  test "the new-team form hides roles carrying a dangerous permission" do
    sign_in_as users(:member), manageable: [ @guild ]

    with_fake_api { get new_guild_team_path(@guild) }

    assert_response :success
    assert_select "option[value=?]", "111" # plain role offered
    assert_select "option[value=?]", "222" # harmless-permission role offered
    assert_select "option[value=?]", "999", count: 0 # Administrator role filtered out
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

  test "a crafted POST naming an Administrator officer role is rejected" do
    sign_in_as users(:member), manageable: [ @guild ]

    with_fake_api do
      post guild_teams_path(@guild), params: { team: {
        name: "Sneaky", team_role_id: "111", officer_role_id: "999", review_channel_id: "700"
      } }
    end

    assert_response :unprocessable_entity
    assert_match(/from the lists/, flash[:alert])
    assert_empty teams
  end
end
