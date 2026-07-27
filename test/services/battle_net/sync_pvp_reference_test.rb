require "test_helper"

module BattleNet
  class SyncPvpReferenceTest < ActiveSupport::TestCase
    NOW = Time.utc(2026, 7, 27)

    class FakeClient
      def initialize(seasons:, current:, tiers: {}, rewards: [])
        @seasons = seasons
        @current = current
        @tiers = tiers
        @rewards = rewards
      end

      def pvp_season_index
        { "seasons" => @seasons.map { |id| { "id" => id } },
          "current_pvp_season" => { "id" => @current } }
      end

      def pvp_season(id)
        { "season_name" => "Player vs. Player (Season #{id})",
          "season_start_timestamp" => Time.utc(2026, 3, 17).to_i * 1000 }
      end

      def pvp_tier_index = { "tiers" => @tiers.keys.map { |id| { "id" => id, "name" => @tiers[id][:name] } } }

      def pvp_tier(id)
        t = @tiers.fetch(id)
        { "name" => t[:name], "min_rating" => t[:min], "max_rating" => 0,
          "bracket" => { "type" => t[:bracket] } }
      end

      def pvp_rewards(_season_id) = { "rewards" => @rewards }
    end

    def reward(cutoff:, bracket: "SHUFFLE", spec_id: 581, spec: "Vengeance")
      { "bracket" => { "type" => bracket }, "rating_cutoff" => cutoff,
        "specialization" => { "id" => spec_id, "name" => spec },
        "achievement" => { "name" => "Galactic Legend: Midnight Season 1" } }
    end

    def client(**overrides)
      FakeClient.new(**{ seasons: [ 39, 40, 41 ], current: 41 }.merge(overrides))
    end

    def sync(c = client) = SyncPvpReference.call(client: c, now: NOW)

    test "records every season and marks exactly one current" do
      result = sync

      assert_equal 3, result.seasons
      assert_equal 41, WowPvpSeason.current.blizzard_id
      assert_equal 1, WowPvpSeason.where(current: true).count
    end

    test "a season rollover moves the current flag" do
      sync
      sync(client(seasons: [ 39, 40, 41, 42 ], current: 42))

      assert_equal 42, WowPvpSeason.current.blizzard_id
      assert_equal 1, WowPvpSeason.where(current: true).count
      assert_not WowPvpSeason.find_by(blizzard_id: 41).current?
    end

    test "season names are trimmed to what a person would say" do
      sync

      assert_equal "Season 41", WowPvpSeason.current.display_name
    end

    test "tiers carry the rating they start at" do
      sync(client(tiers: { 14 => { name: "Elite", min: 2275, bracket: "ARENA_3v3" },
                           13 => { name: "Duelist", min: 2075, bracket: "ARENA_3v3" } }))

      assert_equal "Elite (2275+)", WowPvpTier.find_by(blizzard_id: 14).label
      assert_equal %w[Duelist Elite], WowPvpTier.by_rating.map(&:name)
    end

    # --- Cutoffs: the reason any of this is stored ---

    test "records a cutoff per bracket and specialisation" do
      result = sync(client(rewards: [
        reward(cutoff: 2205, spec_id: 581, spec: "Vengeance"),
        reward(cutoff: 2998, spec_id: 72, spec: "Fury"),
        reward(cutoff: 1900, bracket: "ARENA_3v3", spec_id: nil, spec: nil)
      ]))

      assert_equal 3, result.cutoffs
      assert_equal 2205, WowPvpCutoff.latest_for(season_id: 41, bracket_type: "SHUFFLE",
                                                 specialization_id: 581).rating_cutoff
      assert_equal 1900, WowPvpCutoff.latest_for(season_id: 41, bracket_type: "ARENA_3v3").rating_cutoff
    end

    # Cutoffs drift all season. A moved bar is new information, not an update —
    # storing the step history is the point.
    test "a moved cutoff adds a row rather than overwriting" do
      sync(client(rewards: [ reward(cutoff: 2205) ]))
      result = sync(client(rewards: [ reward(cutoff: 2260) ]))

      assert_equal 1, result.cutoffs, "only the change counts"
      assert_equal 2, WowPvpCutoff.count
      assert_equal 2260, WowPvpCutoff.latest_for(season_id: 41, bracket_type: "SHUFFLE",
                                                 specialization_id: 581).rating_cutoff
    end

    test "an unchanged cutoff costs no new row" do
      sync(client(rewards: [ reward(cutoff: 2205) ]))
      result = sync(client(rewards: [ reward(cutoff: 2205) ]))

      assert_equal 0, result.cutoffs
      assert_equal 1, WowPvpCutoff.count
    end

    test "a reward with no cutoff yet is skipped" do
      result = sync(client(rewards: [ { "bracket" => { "type" => "SHUFFLE" } } ]))

      assert_equal 0, result.cutoffs
    end
  end
end
