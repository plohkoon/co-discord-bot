require "test_helper"

module Discord
  class GuildHealthTest < ActiveSupport::TestCase
    GUILD_ID = 100
    BOT_ROLE_ID = "10"
    TEAM_ROLE_ID = 20

    # Stands in for Discord::BotApi. Roles/member mirror Discord's REST shapes.
    class FakeApi
      def initialize(roles:, member:, configured: true, error: nil)
        @roles = roles
        @member = member
        @configured = configured
        @error = error
      end

      def configured? = @configured
      def bot_user_id = "999"

      def guild_roles(_guild_id)
        raise @error if @error
        @roles
      end

      def guild_member(_guild_id, _user_id) = @member
    end

    MANAGE_ROLES = Discord::GuildHealth::MANAGE_ROLES

    def guild = @guild ||= Guild.sync_from_discord(id: GUILD_ID, name: "Test")

    def team
      @team ||= ActsAsTenant.with_tenant(guild) do
        Team.create!(name: "Alpha", team_role_id: TEAM_ROLE_ID, officer_role_id: 30, review_channel_id: 40)
      end
    end

    def roles(bot_position: 5, bot_permissions: MANAGE_ROLES, team_role: true)
      list = [
        { "id" => GUILD_ID.to_s, "name" => "@everyone", "position" => 0, "permissions" => "0" },
        { "id" => BOT_ROLE_ID, "name" => "co-bot", "position" => bot_position, "permissions" => bot_permissions.to_s }
      ]
      list << { "id" => TEAM_ROLE_ID.to_s, "name" => "Alpha Team", "position" => 3, "permissions" => "0" } if team_role
      list
    end

    def member = { "roles" => [ BOT_ROLE_ID ] }

    def check(api) = GuildHealth.new(guild: guild, teams: [ team ], api: api).call

    test "healthy guild reports ok" do
      health = check(FakeApi.new(roles: roles, member: member))
      assert_equal :ok, health[:status]
      assert_empty health[:problems]
    end

    test "missing Manage Roles is reported" do
      health = check(FakeApi.new(roles: roles(bot_permissions: 0), member: member))
      assert_equal :issues, health[:status]
      assert health[:problems].any? { |p| p[:summary].include?("Manage Roles") }
    end

    test "administrator satisfies the permission check" do
      admin = Discord::GuildHealth::ADMINISTRATOR
      health = check(FakeApi.new(roles: roles(bot_permissions: admin), member: member))
      assert_equal :ok, health[:status]
    end

    test "team role above the bot's highest role is reported" do
      health = check(FakeApi.new(roles: roles(bot_position: 2), member: member))
      assert_equal :issues, health[:status]
      assert health[:problems].any? { |p| p[:summary].include?("Alpha") }
    end

    test "deleted team role is reported" do
      health = check(FakeApi.new(roles: roles(team_role: false), member: member))
      assert_equal :issues, health[:status]
      assert health[:problems].any? { |p| p[:summary].include?("no longer exists") }
    end

    test "a 404 marks the guild removed" do
      health = check(FakeApi.new(roles: nil, member: nil, error: BotApi::NotFound.new("gone")))
      assert_equal :removed, health[:status]
      assert guild.reload.removed?
    end

    test "an unconfigured token reports unknown without warning" do
      health = check(FakeApi.new(roles: nil, member: nil, configured: false))
      assert_equal :unknown, health[:status]
    end

    test "a network error reports unknown and does not mark the guild removed" do
      health = check(FakeApi.new(roles: nil, member: nil, error: BotApi::Error.new("timeout")))
      assert_equal :unknown, health[:status]
      assert_not guild.reload.removed?
    end
  end
end
