require "test_helper"

module BattleNet
  class RefreshCharacterProfessionsTest < ActiveSupport::TestCase
    NOW = Time.utc(2026, 7, 27)

    class FakeClient
      attr_reader :calls

      def initialize(payload, error: nil)
        @payload = payload
        @error = error
        @calls = 0
      end

      def character_professions(_realm, _name)
        @calls += 1
        raise @error if @error

        @payload
      end
    end

    def tier(id, name, skill: 100, max: 100, recipes: 0)
      { "tier" => { "id" => id, "name" => name }, "skill_points" => skill,
        "max_skill_points" => max, "known_recipes" => Array.new(recipes) { |i| { "id" => i } } }
    end

    def profession(id, name, tiers)
      { "profession" => { "id" => id, "name" => name }, "tiers" => tiers }
    end

    def payload(primaries: nil, secondaries: nil)
      { "primaries" => primaries || [
          profession(197, "Tailoring", [ tier(2910, "Midnight Tailoring", skill: 30, recipes: 21),
                                         tier(2506, "Classic Tailoring", skill: 300, max: 300, recipes: 6) ])
        ],
        "secondaries" => secondaries || [ profession(185, "Cooking", [ tier(2911, "Midnight Cooking") ]) ] }
    end

    def account
      @account ||= users(:member).battle_net_accounts.create!(battle_net_id: 1, region: "us", linked_at: NOW)
    end

    def character
      @character ||= account.wow_characters.create!(
        blizzard_id: 42, name: "Jörmûngandr", realm: "Sargeras", realm_slug: "sargeras",
        level: 90, verified_at: NOW
      )
    end

    def refresh(data = payload, error: nil, now: NOW, **opts)
      client = FakeClient.new(data, error: error)
      [ RefreshCharacterProfessions.call(character, client: client, now: now, **opts), client ]
    end

    test "records primaries and secondaries with their tiers" do
      result, = refresh

      assert result.ok?
      assert_equal 2, result.professions
      assert_equal %w[Cooking Tailoring], character.professions.map(&:name)
      assert_equal "primary", character.wow_character_professions.find_by(name: "Tailoring").kind
      assert_equal "secondary", character.wow_character_professions.find_by(name: "Cooking").kind
      assert_equal 2, character.wow_character_professions.find_by(name: "Tailoring")
                               .wow_character_profession_tiers.count
    end

    test "the summary quotes the primaries at their latest tier" do
      refresh

      assert_equal "Tailoring 30/100", character.profession_summary
      assert_equal 21, character.wow_character_professions.find_by(name: "Tailoring")
                                .latest_tier.known_recipe_count
    end

    # Blizzard doesn't flag the current tier and the ids are not chronological
    # in general, but the newest expansion always takes the highest id.
    test "the latest tier is the newest expansion, not the highest skill" do
      refresh

      tailoring = character.wow_character_professions.find_by(name: "Tailoring")
      assert_equal "Midnight Tailoring", tailoring.latest_tier.name,
                   "Classic is capped at 300/300 but is not current"
      assert_not tailoring.latest_tier.maxed?
      assert tailoring.wow_character_profession_tiers.find_by(tier_id: 2506).maxed?
    end

    test "classifies crafting and gathering professions" do
      refresh(payload(primaries: [ profession(197, "Tailoring", [ tier(2910, "Midnight Tailoring") ]),
                                   profession(186, "Mining", [ tier(2912, "Midnight Mining") ]) ]))

      assert character.wow_character_professions.find_by(name: "Tailoring").crafting?
      assert character.wow_character_professions.find_by(name: "Mining").gathering?
      assert_equal [ "Tailoring" ], character.wow_character_professions.crafting.pluck(:name)
      assert character.profession?("Mining")
    end

    # Professions are droppable — someone who abandons Enchanting for Alchemy
    # must stop showing as an enchanter.
    test "a dropped profession is removed" do
      refresh(payload(primaries: [ profession(333, "Enchanting", [ tier(2900, "Midnight Enchanting") ]) ]))
      assert character.profession?("Enchanting")

      refresh(payload(primaries: [ profession(171, "Alchemy", [ tier(2901, "Midnight Alchemy") ]) ]),
              now: NOW + 8.days)

      assert_not character.profession?("Enchanting")
      assert character.profession?("Alchemy")
      assert_equal 1, character.wow_character_professions.primary.count
    end

    test "re-running updates skill in place rather than duplicating" do
      refresh
      refresh(payload(primaries: [ profession(197, "Tailoring", [ tier(2910, "Midnight Tailoring", skill: 75) ]) ]),
              now: NOW + 8.days)

      tailoring = character.wow_character_professions.find_by(name: "Tailoring")
      assert_equal 75, tailoring.latest_tier.skill_points
      assert_equal 1, tailoring.wow_character_profession_tiers.count, "the dropped tier is pruned"
    end

    # Professions move at the speed of someone deciding to level Enchanting, so
    # the hourly refresh must not re-ask every pass.
    test "a recent refresh is skipped without a request" do
      refresh
      result, client = refresh

      assert_equal :skipped, result.status
      assert_equal 0, client.calls
    end

    test "a stale refresh does ask again" do
      refresh
      result, client = refresh(now: NOW + 8.days)

      assert result.ok?
      assert_equal 1, client.calls
    end

    test "a character with no professions records none and is still stamped" do
      result, = refresh({ "primaries" => [], "secondaries" => [] })

      assert result.ok?
      assert_empty character.professions
      assert character.reload.professions_refreshed_at.present?
    end

    test "a character Blizzard no longer knows is stamped so the sweep moves on" do
      result, = refresh(nil, error: Client::NotFound)

      assert_equal :missing, result.status
      assert character.reload.professions_refreshed_at.present?
    end

    # --- Known recipes ---

    test "known recipe ids are stored as a thin join, not duplicated names" do
      refresh(payload(primaries: [
        profession(171, "Alchemy", [ { "tier" => { "id" => 2906, "name" => "Midnight Alchemy" },
                                       "skill_points" => 98, "max_skill_points" => 100,
                                       "known_recipes" => [ { "id" => 52_786, "name" => "Sunsmoke Censer" },
                                                            { "id" => 52_781, "name" => "Recycle Potions" } ] } ])
      ]))

      assert_equal [ 52_781, 52_786 ], character.wow_character_recipes.pluck(:recipe_id).sort
      assert character.knows_recipe?(52_786)
      assert_equal 2, character.known_recipe_count
    end

    # Dropping a profession takes its recipes with it, so the known set is
    # reconciled in full rather than added to.
    test "recipes of a dropped profession are removed" do
      with_recipes = ->(ids) {
        payload(primaries: [
          profession(171, "Alchemy", [ { "tier" => { "id" => 2906, "name" => "Midnight Alchemy" },
                                         "known_recipes" => ids.map { |i| { "id" => i } } } ])
        ])
      }
      refresh(with_recipes.call([ 1, 2, 3 ]))
      assert_equal 3, character.known_recipe_count

      refresh(payload(primaries: [ profession(197, "Tailoring", [ tier(2910, "Midnight Tailoring") ]) ]),
              now: NOW + 8.days)

      assert_equal 0, character.wow_character_recipes.count
      assert_not character.profession?("Alchemy")
    end

    test "malformed entries are skipped rather than failing the batch" do
      result, = refresh({ "primaries" => [ profession(197, "Tailoring", [ tier(2910, "Midnight Tailoring") ]),
                                           { "profession" => { "id" => 9 } },
                                           { "tiers" => [] } ] })

      assert result.ok?
      assert_equal 1, result.professions
    end
  end
end
