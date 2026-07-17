require "test_helper"

class TeamCategoryTest < ActiveSupport::TestCase
  def guild = @guild ||= Guild.sync_from_discord(id: 1, name: "Test")

  test "named finds case-insensitively and never creates" do
    ActsAsTenant.with_tenant(guild) do
      category = TeamCategory.create!(name: "PvE Teams ⚔️")

      assert_equal category.id, TeamCategory.named("pve teams ⚔️").id
      assert_nil TeamCategory.named("Raids")
      assert_nil TeamCategory.named("   ")
      assert_equal 1, TeamCategory.count
    end
  end

  test "a blank position appends to the end of the order" do
    ActsAsTenant.with_tenant(guild) do
      first = TeamCategory.create!(name: "PvE Teams", position: nil)
      second = TeamCategory.create!(name: "PvP Teams", position: nil)

      assert_operator first.position, :<, second.position
      assert_equal %w[PvE\ Teams PvP\ Teams], TeamCategory.ordered.pluck(:name)
    end
  end
end
