require "test_helper"

module BattleNet
  class RefreshCharacterPvpTest < ActiveSupport::TestCase
    NOW = Time.utc(2026, 7, 27)
    SEASON = 41

    class FakeClient
      attr_reader :brackets_asked

      def initialize(summary:, brackets: {}, error: nil)
        @summary = summary
        @brackets = brackets
        @error = error
        @brackets_asked = []
      end

      def pvp_summary(_realm, _name)
        raise @error if @error

        @summary
      end

      def pvp_bracket(_realm, _name, bracket)
        @brackets_asked << bracket
        payload = @brackets.fetch(bracket, :missing)
        raise Client::NotFound, bracket if payload == :missing

        payload
      end
    end

    # The `brackets` list is link objects; the slug is the tail of the href.
    def summary(*slugs, honor: 1789, kills: 7105)
      { "honor_level" => honor, "honorable_kills" => kills,
        "brackets" => slugs.map { |s| { "href" => "https://us.api.blizzard.com/profile/wow/character/x/y/pvp-bracket/#{s}?namespace=profile-us" } } }
    end

    def bracket(rating:, tier: 14, played: 391, won: 251, lost: 140, weekly: 26, season: SEASON)
      { "rating" => rating, "tier" => { "id" => tier }, "season" => { "id" => season },
        "season_match_statistics" => { "played" => played, "won" => won, "lost" => lost },
        "weekly_match_statistics" => { "played" => weekly, "won" => weekly, "lost" => 0 } }
    end

    def seed_season! = WowPvpSeason.create!(blizzard_id: SEASON, name: "PvP (Midnight Season 1)", current: true)

    def account
      @account ||= users(:member).battle_net_accounts.create!(battle_net_id: 1, region: "us", linked_at: NOW)
    end

    def character
      @character ||= account.wow_characters.create!(
        blizzard_id: 42, name: "Dxdx", realm: "Dragonblight", realm_slug: "dragonblight",
        level: 90, verified_at: NOW
      )
    end

    def refresh(client)
      [ RefreshCharacterPvp.call(character, client: client, now: NOW), client ]
    end

    # --- The bracket fan-out ---

    # pvp-summary states exactly which brackets exist, so nothing is guessed and
    # no 404-probing is needed.
    test "queries exactly the brackets the summary lists" do
      seed_season!
      _r, client = refresh(FakeClient.new(
        summary: summary("3v3", "2v2", "shuffle-mage-frost"),
        brackets: { "3v3" => bracket(rating: 3163), "2v2" => bracket(rating: 1853),
                    "shuffle-mage-frost" => bracket(rating: 2122) }
      ))

      assert_equal %w[3v3 2v2 shuffle-mage-frost], client.brackets_asked
    end

    # The structural difference from PvE: one character, many ratings.
    test "stores a separate rating per specialisation for shuffle and blitz" do
      seed_season!
      refresh(FakeClient.new(
        summary: summary("shuffle-mage-frost", "shuffle-mage-fire", "blitz-mage-frost"),
        brackets: { "shuffle-mage-frost" => bracket(rating: 2122),
                    "shuffle-mage-fire" => bracket(rating: 1728),
                    "blitz-mage-frost" => bracket(rating: 1764) }
      ))

      ratings = character.pvp_ratings
      assert_equal 3, ratings.size
      assert_equal %w[shuffle shuffle blitz].sort, ratings.map(&:bracket_type).sort
      assert_equal %w[mage-fire mage-frost mage-frost].sort, ratings.map(&:spec_slug).sort
      assert_equal 2122, character.pvp_rating, "best across brackets leads"
    end

    test "parses bracket slugs into type and spec" do
      assert_equal [ "3v3", nil ], WowCharacterPvpRating.parse_bracket("3v3")
      assert_equal [ "rbg", nil ], WowCharacterPvpRating.parse_bracket("rbg")
      assert_equal [ "shuffle", "mage-frost" ], WowCharacterPvpRating.parse_bracket("shuffle-mage-frost")
      assert_equal [ "blitz", "demonhunter-devourer" ], WowCharacterPvpRating.parse_bracket("blitz-demonhunter-devourer")
    end

    test "reads names a person would recognise off the stored slug" do
      seed_season!
      refresh(FakeClient.new(summary: summary("shuffle-mage-frost", "rbg"),
                             brackets: { "shuffle-mage-frost" => bracket(rating: 2122),
                                         "rbg" => bracket(rating: 1600) }))

      labels = character.pvp_ratings.map(&:display_bracket)
      assert_includes labels, "Solo Shuffle (Mage Frost)"
      assert_includes labels, "RBG"
    end

    # --- What gets stored ---

    test "stores rating, tier, and season and weekly records" do
      seed_season!
      WowPvpTier.create!(blizzard_id: 14, name: "Elite", min_rating: 2275, bracket_type: "ARENA_3v3")
      refresh(FakeClient.new(summary: summary("3v3"), brackets: { "3v3" => bracket(rating: 3163) }))

      row = character.pvp_ratings.sole
      assert_equal 3163, row.rating
      assert_equal "Elite", row.tier_name
      assert_equal 391, row.played
      assert_equal 64, row.win_rate
      assert_equal 26, row.weekly_played
      assert row.played_this_week?
    end

    test "records honor level and lifetime kills on the character" do
      seed_season!
      refresh(FakeClient.new(summary: summary(honor: 1789, kills: 7105)))

      character.reload
      assert_equal 1789, character.honor_level
      assert_equal 7105, character.honorable_kills
      assert character.pvp_refreshed_at.present?
    end

    test "re-running updates in place rather than duplicating" do
      seed_season!
      refresh(FakeClient.new(summary: summary("3v3"), brackets: { "3v3" => bracket(rating: 3100) }))
      refresh(FakeClient.new(summary: summary("3v3"), brackets: { "3v3" => bracket(rating: 3163) }))

      assert_equal 1, character.wow_character_pvp_ratings.count
      assert_equal 3163, character.pvp_rating
    end

    # A season rollover mid-sweep must not file a new rating under the old
    # season — the payload's own season id wins.
    test "the season on the payload wins over the one we assumed" do
      seed_season!
      refresh(FakeClient.new(summary: summary("3v3"),
                             brackets: { "3v3" => bracket(rating: 1500, season: 42) }))

      assert_equal 42, character.wow_character_pvp_ratings.sole.season_id
    end

    # --- The cheap path ---

    test "a character with no rated play costs one request and stores nothing" do
      seed_season!
      result, client = refresh(FakeClient.new(summary: summary(honor: 3, kills: 352)))

      assert result.ok?
      assert_equal 0, result.brackets_fetched
      assert_empty client.brackets_asked
      assert_empty character.wow_character_pvp_ratings
      assert_equal 3, character.reload.honor_level
      assert_not character.pvp?
    end

    test "with no season synced yet nothing is stored but honor still lands" do
      result, client = refresh(FakeClient.new(summary: summary("3v3"), brackets: { "3v3" => bracket(rating: 3163) }))

      assert result.ok?
      assert_empty client.brackets_asked, "the reference sync has to run first"
      assert_equal 1789, character.reload.honor_level
    end

    # --- Failure modes ---

    test "a bracket listed but not queryable is skipped, not fatal" do
      seed_season!
      result, = refresh(FakeClient.new(summary: summary("3v3", "rbg"),
                                       brackets: { "3v3" => bracket(rating: 3163) }))

      assert result.ok?
      assert_equal 1, result.brackets_fetched
      assert_equal [ "3v3" ], character.pvp_ratings.map(&:bracket)
    end

    test "a character Blizzard no longer knows reports missing" do
      seed_season!
      result, = refresh(FakeClient.new(summary: nil, error: Client::NotFound))

      assert_equal :missing, result.status
      assert_empty character.wow_character_pvp_ratings
    end
  end
end
