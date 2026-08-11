require "test_helper"

module BattleNet
  class RefreshCharacterAchievementsTest < ActiveSupport::TestCase
    NOW = Time.utc(2026, 7, 27)

    class FakeClient
      def initialize(achievements, error: nil)
        @achievements = achievements
        @error = error
      end

      def character_achievements(_realm, _name)
        raise @error if @error

        { "achievements" => @achievements }
      end
    end

    def entry(id, name, completed: Time.utc(2026, 5, 1))
      row = { "achievement" => { "id" => id, "name" => name } }
      row["completed_timestamp"] = completed.to_i * 1000 if completed
      row
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

    def refresh(achievements, error: nil)
      RefreshCharacterAchievements.call(character, client: FakeClient.new(achievements, error: error), now: NOW)
    end

    test "keeps career credentials and discards the rest" do
      result = refresh([
        entry(1, "Cutting Edge: Dimensius, the All-Devouring"),
        entry(2, "Ahead of the Curve: N'Zoth the Corruptor"),
        entry(3, "Keystone Master"),
        entry(4, "Level 60"),
        entry(5, "Loremaster of Kalimdor")
      ])

      assert result.ok?
      assert_equal 3, result.stored
      assert_equal 5, result.scanned
      assert_equal %w[aotc cutting_edge keystone], character.wow_character_achievements.pluck(:category).sort
    end

    # Blizzard mints a per-dungeon "Keystone Hero: <dungeon>" for every dungeon.
    # One live character had 39 of those against 3 real titles — a completion
    # log, not a credential.
    test "per-dungeon keystone achievements are not credentials" do
      refresh([
        entry(1, "Keystone Master"),
        entry(2, "Keystone Hero: Seat of the Triumvirate"),
        entry(3, "Keystone Hero: Nexus-Point Xenas")
      ])

      assert_equal [ "Keystone Master" ], character.wow_character_achievements.pluck(:name)
    end

    # "Darkmoon Duelist" is a real, unrelated achievement — which is why the
    # evergreen PvP titles match by id, not by name.
    test "PvP titles match by id so lookalike names are not miscategorised" do
      refresh([
        entry(2092, "Duelist"),
        entry(6023, "Darkmoon Duelist"),
        entry(2091, "Gladiator")
      ])

      names = character.wow_character_achievements.pluck(:name)
      assert_includes names, "Duelist"
      assert_includes names, "Gladiator"
      assert_not_includes names, "Darkmoon Duelist"
    end

    test "seasonal gladiator mounts are kept and categorised as gladiator" do
      refresh([ entry(14_816, "Sinful Gladiator's Soul Eater") ])

      row = character.wow_character_achievements.sole
      assert_equal "gladiator", row.category
      assert character.gladiator?
    end

    # An achievement someone is working towards is not a credential.
    test "unearned achievements are skipped" do
      result = refresh([ entry(1, "Cutting Edge: Dimensius", completed: nil) ])

      assert_equal 0, result.stored
      assert_empty character.wow_character_achievements
    end

    # The date is the claim — "Cutting Edge in 2024" differs from "eventually".
    test "the completion date is stored and travels with the name" do
      refresh([ entry(1, "Cutting Edge: Dimensius", completed: Time.utc(2024, 4, 12)) ])

      row = character.wow_character_achievements.sole
      assert_equal Date.new(2024, 4, 12), row.earned_on
      assert_equal "Cutting Edge: Dimensius (Apr 2024)", row.summary
    end

    test "cutting edge outranks AOTC as the headline credential" do
      refresh([
        entry(1, "Ahead of the Curve: Midnight Falls", completed: Time.utc(2026, 5, 1)),
        entry(2, "Cutting Edge: Chimaerus", completed: Time.utc(2024, 1, 1))
      ])

      assert_equal "Cutting Edge: Chimaerus", character.best_raid_credential.name,
                   "an older CE still beats a newer AOTC"
      assert character.cutting_edge?
      assert character.aotc?
    end

    test "re-running updates in place rather than duplicating" do
      refresh([ entry(1, "Keystone Master") ])
      refresh([ entry(1, "Keystone Master") ])

      assert_equal 1, character.wow_character_achievements.count
      assert character.reload.achievements_refreshed_at.present?
    end

    test "a character Blizzard no longer knows is stamped so the sweep moves on" do
      result = refresh([], error: Client::NotFound)

      assert_equal :missing, result.status
      assert character.reload.achievements_refreshed_at.present?
    end

    test "malformed entries are skipped rather than failing the batch" do
      result = refresh([
        entry(1, "Keystone Master"),
        { "completed_timestamp" => 1 },
        { "achievement" => { "id" => 9 }, "completed_timestamp" => 1 }
      ])

      assert result.ok?
      assert_equal 1, result.stored
    end
  end
end
