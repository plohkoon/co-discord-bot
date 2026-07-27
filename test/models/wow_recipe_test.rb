require "test_helper"

# The point of splitting the catalog from the join: answering "who knows this"
# in one hop, and — just as importantly — telling "nobody knows it" apart from
# "that isn't a recipe".
class WowRecipeTest < ActiveSupport::TestCase
  NOW = Time.utc(2026, 7, 27)

  def account(user = users(:member))
    user.battle_net_accounts.find_or_create_by!(battle_net_id: user.id) do |a|
      a.region = "us"
      a.linked_at = NOW
    end
  end

  def character(name, user: users(:member), level: 90)
    account(user).wow_characters.create!(
      blizzard_id: name.hash.abs, name: name, realm: "Sargeras", realm_slug: "sargeras",
      level: level, verified_at: NOW
    )
  end

  def recipe(id, name, **attrs)
    WowRecipe.create!({ recipe_id: id, name: name, profession_name: "Alchemy",
                        skill_tier_name: "Midnight Alchemy", category: "Void Potions",
                        skill_tier_id: 2906, profession_id: 171 }.merge(attrs))
  end

  test "known_by lists the characters that have learned it" do
    censer = recipe(52_786, "Sunsmoke Censer")
    knower = character("Jörmûngandr")
    character("Morhigahn") # doesn't know it
    knower.wow_character_recipes.create!(recipe_id: 52_786)

    assert_equal [ "Jörmûngandr" ], censer.known_by.map(&:name)
    assert_equal 1, censer.known_by_count
    assert knower.knows_recipe?(52_786)
  end

  # The whole reason the catalog is synced from static data rather than built
  # from what characters happen to know.
  test "a catalogued recipe nobody knows answers zero, not missing" do
    orphan = recipe(60_000, "Monel-Hardened Boots", profession_name: "Blacksmithing")

    assert_equal 0, orphan.known_by_count
    assert_empty orphan.known_by
    assert WowRecipe.exists?(recipe_id: 60_000), "still a known recipe, just unlearned"
  end

  test "name search is case-insensitive and matches partials" do
    recipe(52_786, "Sunsmoke Censer")

    assert_equal [ "Sunsmoke Censer" ], WowRecipe.matching("sunsmoke").map(&:name)
    assert_equal [ "Sunsmoke Censer" ], WowRecipe.matching("CENSER").map(&:name)
    assert_empty WowRecipe.matching("nonsense")
    assert_empty WowRecipe.matching(""), "a blank search must not return the whole catalog"
  end

  test "recipes known by several characters list them all" do
    censer = recipe(52_786, "Sunsmoke Censer")
    %w[Jörmûngandr Morhigahn].each do |name|
      character(name).wow_character_recipes.create!(recipe_id: 52_786)
    end

    assert_equal 2, censer.known_by_count
  end

  # Any answer here is bounded by who has linked Battle.net — "nobody knows it"
  # and "the person who knows it never linked" are indistinguishable, so the
  # coverage has to travel with the result.
  test "coverage reports how much of the population this can speak for" do
    character("Jörmûngandr").wow_character_recipes.create!(recipe_id: 52_786)
    character("Greg", user: users(:admin)).wow_character_recipes.create!(recipe_id: 52_786)

    coverage = WowCharacterRecipe.coverage
    assert_equal 2, coverage.linked_characters
    assert_equal 2, coverage.linked_users
  end

  # Blizzard can report a recipe the catalog sync hasn't reached yet; an
  # unlabelled row beats a dropped one.
  test "a known recipe missing from the catalog is still stored" do
    knower = character("Jörmûngandr")
    knower.wow_character_recipes.create!(recipe_id: 99_999)

    row = knower.wow_character_recipes.sole
    assert_nil row.wow_recipe
    assert_equal 99_999, row.recipe_id
  end
end
