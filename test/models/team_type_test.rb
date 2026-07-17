require "test_helper"

class TeamTypeTest < ActiveSupport::TestCase
  test "a new guild is seeded with the stock team types, once" do
    guild = Guild.sync_from_discord(id: 1, name: "Test")
    Guild.sync_from_discord(id: 1, name: "Test") # resync doesn't duplicate
    guild.seed_default_team_types!               # nor does an explicit re-seed

    ActsAsTenant.with_tenant(guild) do
      assert_equal TeamType::DEFAULT_NAMES, TeamType.ordered.pluck(:name)
    end
  end

  test "named finds case-insensitively and never creates" do
    guild = Guild.sync_from_discord(id: 1, name: "Test")

    ActsAsTenant.with_tenant(guild) do
      assert_equal "Heroic Team", TeamType.named("heroic team").name
      assert_nil TeamType.named("Casual Team")
      assert_nil TeamType.named("   ")
      assert_equal TeamType::DEFAULT_NAMES.size, TeamType.count
    end
  end

  test "a blank position appends after the seeded defaults" do
    guild = Guild.sync_from_discord(id: 1, name: "Test")

    ActsAsTenant.with_tenant(guild) do
      added = TeamType.create!(name: "Casual Team", position: nil)
      assert_equal TeamType::DEFAULT_NAMES + [ "Casual Team" ], TeamType.ordered.pluck(:name)
      assert_operator added.position, :>, TeamType.named("PvP Team").position
    end
  end
end
