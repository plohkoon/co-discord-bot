require "test_helper"

module Discord
  class ManageableGuildsTest < ActiveSupport::TestCase
    MANAGE = ManageableGuilds::MANAGE_GUILD

    # The service with Discord's HTTP swapped out for a canned guild list.
    class Offline < ManageableGuilds
      def initialize(guilds:)
        super(token: "token")
        @guilds = guilds
      end

      private

      def fetch = @guilds
    end

    def discord_guilds
      [
        { "id" => "1", "name" => "Installed",   "icon" => nil,   "owner" => false, "permissions" => MANAGE.to_s },
        { "id" => "2", "name" => "Installable", "icon" => "abc", "owner" => false, "permissions" => MANAGE.to_s },
        { "id" => "3", "name" => "NotManager",  "icon" => nil,   "owner" => false, "permissions" => "0" },
        { "id" => "4", "name" => "Owned",       "icon" => nil,   "owner" => true,  "permissions" => "0" }
      ]
    end

    def call_with(guilds) = Offline.new(guilds: guilds).call

    test "partitions managed guilds by whether a Guild row exists" do
      Guild.sync_from_discord(id: 1, name: "Installed")

      result = call_with(discord_guilds)

      assert_equal [ "1" ], result.manageable.map { |g| g["id"] }
      assert_equal %w[2 4], result.installable.map { |g| g["id"] }.sort
    end

    test "guilds without Manage Server are dropped entirely" do
      result = call_with(discord_guilds)
      all_ids = (result.manageable + result.installable).map { |g| g["id"] }
      assert_not_includes all_ids, "3"
    end

    test "removed guilds still count as manageable for the re-invite flow" do
      Guild.sync_from_discord(id: 1, name: "Installed").mark_removed!

      result = call_with(discord_guilds)

      assert_includes result.manageable.map { |g| g["id"] }, "1"
      assert_not_includes result.installable.map { |g| g["id"] }, "1"
    end

    test "entries carry only id, name, and icon" do
      result = call_with(discord_guilds)
      entry = result.installable.find { |g| g["id"] == "2" }
      assert_equal({ "id" => "2", "name" => "Installable", "icon" => "abc" }, entry)
    end
  end
end
