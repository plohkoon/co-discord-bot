require "test_helper"

module BattleNet
  class SyncRecipeCatalogTest < ActiveSupport::TestCase
    NOW = Time.utc(2026, 7, 27)

    class FakeClient
      attr_reader :tiers_asked

      # professions: [{id:, name:, tiers: [{id:, name:, recipes: {category => [[id, name], ...]}}]}]
      def initialize(professions, error: nil)
        @professions = professions
        @error = error
        @tiers_asked = []
      end

      def profession_index
        { "professions" => @professions.map { |p| { "id" => p[:id], "name" => p[:name] } } }
      end

      def profession(id)
        p = find(id)
        raise @error if @error

        { "id" => p[:id], "name" => p[:name],
          "skill_tiers" => p[:tiers].map { |t| { "id" => t[:id], "name" => t[:name] } } }
      end

      def profession_skill_tier(profession_id, skill_tier_id)
        @tiers_asked << skill_tier_id
        tier = find(profession_id)[:tiers].find { |t| t[:id] == skill_tier_id }
        { "categories" => tier[:recipes].map { |cat, list|
          { "name" => cat, "recipes" => list.map { |id, name| { "id" => id, "name" => name } } }
        } }
      end

      private

      def find(id) = @professions.find { |p| p[:id] == id }
    end

    def alchemy(newest_recipes: { "Void Potions" => [ [ 52_786, "Sunsmoke Censer" ] ] })
      [ { id: 171, name: "Alchemy", tiers: [
        { id: 2506, name: "Classic Alchemy", recipes: { "Potions" => [ [ 100, "Healing Potion" ] ] } },
        { id: 2906, name: "Midnight Alchemy", recipes: newest_recipes }
      ] } ]
    end

    def sync(professions, **opts)
      client = FakeClient.new(professions)
      [ SyncRecipeCatalog.call(client: client, now: NOW, **opts), client ]
    end

    test "stores recipes with their profession, tier and category" do
      result, = sync(alchemy)

      assert_equal 2, result.recipes
      recipe = WowRecipe.find_by(recipe_id: 52_786)
      assert_equal "Sunsmoke Censer", recipe.name
      assert_equal "Alchemy", recipe.profession_name
      assert_equal "Midnight Alchemy", recipe.skill_tier_name
      assert_equal "Void Potions", recipe.category
      assert_equal "Sunsmoke Censer · Void Potions · Midnight Alchemy", recipe.summary
    end

    # A closed expansion's recipe list is fixed, so re-reading it is wasted
    # requests. The live tier can still gain recipes in a patch.
    test "a closed tier already stored is not re-read, but the newest always is" do
      sync(alchemy)
      _result, client = sync(alchemy)

      assert_equal [ 2906 ], client.tiers_asked, "only the newest tier"
    end

    test "a newly added recipe in the live tier is picked up" do
      sync(alchemy)
      result, = sync(alchemy(newest_recipes: {
        "Void Potions" => [ [ 52_786, "Sunsmoke Censer" ], [ 52_787, "Void Elixir" ] ]
      }))

      assert_equal 2, result.recipes
      assert WowRecipe.exists?(recipe_id: 52_787)
    end

    test "refresh_all re-reads closed tiers too" do
      sync(alchemy)
      _result, client = sync(alchemy, refresh_all: true)

      assert_equal [ 2506, 2906 ], client.tiers_asked.sort
    end

    test "a renamed recipe is updated in place" do
      sync(alchemy)
      sync(alchemy(newest_recipes: { "Void Potions" => [ [ 52_786, "Sunsmoke Brazier" ] ] }))

      assert_equal 1, WowRecipe.where(recipe_id: 52_786).count
      assert_equal "Sunsmoke Brazier", WowRecipe.find_by(recipe_id: 52_786).name
    end

    test "one profession failing does not cost the others" do
      professions = alchemy + [ { id: 164, name: "Blacksmithing", tiers: [] } ]
      client = FakeClient.new(professions)
      # Make the second profession's detail call blow up.
      client.define_singleton_method(:profession) do |id|
        raise Client::Error, "boom" if id == 164

        { "id" => 171, "name" => "Alchemy",
          "skill_tiers" => [ { "id" => 2906, "name" => "Midnight Alchemy" } ] }
      end

      result = SyncRecipeCatalog.call(client: client, now: NOW)

      assert_equal 2, result.professions
      assert WowRecipe.exists?(recipe_id: 52_786), "Alchemy still landed"
    end

    test "a recipe with no id or name is skipped" do
      result, = sync([ { id: 171, name: "Alchemy", tiers: [
        { id: 2906, name: "Midnight Alchemy",
          recipes: { "Potions" => [ [ 1, "Fine" ], [ nil, "No id" ], [ 2, nil ] ] } }
      ] } ])

      assert_equal 1, result.recipes
    end
  end
end
