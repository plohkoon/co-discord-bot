require "test_helper"

class TeamCategoryTest < ActiveSupport::TestCase
  def guild = @guild ||= Guild.sync_from_discord(id: 1, name: "Test")

  test "locate creates once and reuses case-insensitively, in position order" do
    ActsAsTenant.with_tenant(guild) do
      first = TeamCategory.locate("PvE Teams ⚔️")
      second = TeamCategory.locate("pve teams ⚔️")
      other = TeamCategory.locate("PvP Teams")

      assert_equal first.id, second.id
      assert_equal 2, TeamCategory.count
      assert_operator first.position, :<, other.position
      assert_nil TeamCategory.locate("   ")
    end
  end
end
