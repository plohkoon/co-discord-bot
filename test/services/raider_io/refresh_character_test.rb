require "test_helper"

module RaiderIo
  class RefreshCharacterTest < ActiveSupport::TestCase
    NOW = Time.utc(2026, 7, 27)

    class FakeClient
      attr_reader :calls

      def initialize(payload)
        @payload = payload
        @calls = []
      end

      def character_profile(region:, realm:, name:, fields: nil)
        @calls << { region: region, realm: realm, name: name, fields: Array(fields) }
        raise @payload if @payload.is_a?(Class) && @payload <= StandardError

        @payload
      end

      def season_field_requested
        field = calls.last[:fields].find { |f| f.to_s.start_with?("mythic_plus_scores_by_season") }
        field.to_s.split(":").drop(1)
      end
    end

    def season(slug, all:, tank: 0, healer: 0, dps: 0)
      { "season" => slug,
        "scores" => { "all" => all, "tank" => tank, "healer" => healer, "dps" => dps,
                      "spec_0" => all, "spec_1" => 0 } }
    end

    def payload(*seasons, raids: default_raids, role: "TANK")
      { "name" => "Jörmûngandr", "active_spec_role" => role,
        "mythic_plus_scores_by_season" => seasons,
        "raid_progression" => raids }
    end

    def default_raids
      { "the-venomous-abyss" => { "summary" => "", "total_bosses" => 8,
                                  "normal_bosses_killed" => 0, "heroic_bosses_killed" => 0,
                                  "mythic_bosses_killed" => 0 },
        "sporefall" => { "summary" => "1/1 H", "total_bosses" => 1,
                         "normal_bosses_killed" => 0, "heroic_bosses_killed" => 1,
                         "mythic_bosses_killed" => 0 },
        "tier-mn-1" => { "summary" => "1/9 M", "total_bosses" => 9,
                         "normal_bosses_killed" => 9, "heroic_bosses_killed" => 9,
                         "mythic_bosses_killed" => 1 } }
    end

    # Two ended seasons and one live one, mirroring the real static data.
    def seed_seasons!
      WowSeason.create!(slug: "season-mn-1", short_name: "MN1", ranked: true,
                        starts_at: Time.utc(2026, 3, 24), ends_at: Time.utc(2026, 12, 16))
      WowSeason.create!(slug: "season-tww-3", short_name: "TWW3", ranked: true,
                        starts_at: Time.utc(2025, 8, 12), ends_at: Time.utc(2026, 3, 2))
      WowSeason.create!(slug: "season-tww-2", short_name: "TWW2", ranked: true,
                        starts_at: Time.utc(2025, 2, 25), ends_at: Time.utc(2025, 8, 12))
      # Event variants must never be backfilled.
      WowSeason.create!(slug: "season-tww-3-break-the-meta", ranked: false,
                        starts_at: Time.utc(2026, 1, 1), ends_at: Time.utc(2026, 1, 8))
    end

    def account
      @account ||= users(:member).battle_net_accounts.create!(
        battle_net_id: 1, region: "us", linked_at: NOW
      )
    end

    def character(**overrides)
      account.wow_characters.create!({
        blizzard_id: 42, name: "Jörmûngandr", realm: "Sargeras", realm_slug: "sargeras",
        level: 90, verified_at: NOW
      }.merge(overrides))
    end

    def refresh(char, response)
      client = FakeClient.new(response)
      [ RefreshCharacter.call(char, client: client, now: NOW), client ]
    end

    # --- The caching rule ---

    test "the first refresh backfills every ended season in one request" do
      seed_seasons!
      char = character
      _result, client = refresh(char, payload(
        season("season-mn-1", all: 2903.6, tank: 2903.6),
        season("season-tww-3", all: 3027.8, tank: 3027.8),
        season("season-tww-2", all: 3054.7, tank: 3054.7)
      ))

      assert_equal 1, client.calls.size, "history costs one request, not one per season"
      assert_equal %w[current season-tww-3 season-tww-2], client.season_field_requested
      assert_equal 3, char.wow_character_seasons.count
    end

    # The whole point of the satellite table: a finished season is immutable, so
    # it is fetched once and then only ever read.
    test "a season already stored is never requested again" do
      seed_seasons!
      char = character
      refresh(char, payload(season("season-tww-3", all: 3027.8), season("season-tww-2", all: 3054.7)))

      _result, client = refresh(char.reload, payload(season("season-mn-1", all: 2903.6)))

      assert_equal %w[current], client.season_field_requested,
                   "steady state is the live season and nothing else"
    end

    test "the live season is refreshed every time even though it is stored" do
      seed_seasons!
      char = character
      refresh(char, payload(season("season-mn-1", all: 2800.0)))
      refresh(char.reload, payload(season("season-mn-1", all: 2903.6)))

      assert_equal 1, char.wow_character_seasons.count, "updated in place, not duplicated"
      assert_equal 2904, char.reload.mythic_score
    end

    test "event and re-cut seasons are never backfilled" do
      seed_seasons!
      _result, client = refresh(character, payload(season("season-mn-1", all: 1.0)))

      assert_not_includes client.season_field_requested, "season-tww-3-break-the-meta"
    end

    test "backfill is capped per request and finishes on later passes" do
      seed_seasons!
      12.times { |i| WowSeason.create!(slug: "season-old-#{i}", ranked: true,
                                       starts_at: 5.years.ago, ends_at: 4.years.ago) }
      _result, client = refresh(character, payload(season("season-mn-1", all: 1.0)))

      requested = client.season_field_requested - %w[current]
      assert_equal RefreshCharacter::BACKFILL_LIMIT, requested.size
    end

    # --- What gets stored ---

    test "stores each season's role split as its own row" do
      seed_seasons!
      char = character
      refresh(char, payload(season("season-mn-1", all: 2903.6, tank: 2903.6),
                            season("season-tww-3", all: 3027.8, dps: 3027.8)))

      history = char.reload.season_history
      assert_equal %w[season-mn-1 season-tww-3], history.map(&:season_slug)
      assert_equal "tank", history.first.primary_role
      assert_equal "dps", history.second.primary_role, "role is per-season, not per-character"
      assert_equal 3028, char.peak_score, "peak comes from history, not the current season"
    end

    test "the character keeps a denormalised copy of the live season only" do
      seed_seasons!
      char = character
      refresh(char, payload(season("season-mn-1", all: 2903.6), season("season-tww-3", all: 3027.8)))

      char.reload
      assert_equal 2903.6, char.raider_io_score.to_f, "the live season, not the best one"
      assert_equal "tank", char.raider_io_role
    end

    # Raider.io doesn't promise `current` comes back first, and a backfill puts
    # several seasons in the response.
    test "the live season is identified by elimination, not by position" do
      seed_seasons!
      char = character
      refresh(char, payload(season("season-tww-3", all: 3027.8), # ended, listed FIRST
                            season("season-mn-1", all: 2903.6))) # live, listed second

      assert_equal 2903.6, char.reload.raider_io_score.to_f
    end

    test "stores raid progression per tier, keeping untouched raids" do
      seed_seasons!
      char = character
      refresh(char, payload(season("season-mn-1", all: 1.0)))

      assert_equal 3, char.wow_character_raids.count
      assert_equal 2, char.raid_progress.size, "only attempted raids show"
      assert_equal "1/9 M", char.raid_progress_headline,
                   "one mythic kill outranks a full heroic clear of a smaller raid"
    end

    test "raid kill counts are stored per difficulty, not just the summary" do
      seed_seasons!
      char = character
      refresh(char, payload(season("season-mn-1", all: 1.0)))

      tier = char.wow_character_raids.find_by(raid_slug: "tier-mn-1")
      assert_equal "M", tier.highest_difficulty
      assert_equal 1, tier.mythic_bosses_killed
      assert_equal 9, tier.heroic_bosses_killed
      assert_equal 9, tier.total_bosses
    end

    # --- Failure modes ---

    test "a character Raider.io has never crawled is recorded, not retried forever" do
      seed_seasons!
      char = character
      result, = refresh(char, Client::NotFound)

      assert_equal :unknown, result.status
      assert char.reload.raider_io_refreshed_at.present?
      assert_empty char.wow_character_seasons
    end

    test "rate limiting propagates so the caller can decide" do
      seed_seasons!
      assert_raises(Client::RateLimited) { refresh(character, Client::RateLimited) }
    end

    test "no keys this season reads as no score, not a score of zero" do
      seed_seasons!
      char = character
      refresh(char, payload(season("season-mn-1", all: 0)))

      char.reload
      assert_equal 0, char.raider_io_score, "the real value is still recorded"
      assert_nil char.mythic_score, "but it must not display as a score"
      assert_empty char.season_history, "an unscored season isn't history worth showing"
    end

    test "an empty Raider.io season does not mask a real Blizzard rating" do
      seed_seasons!
      char = character(mythic_rating: 1850.0)
      refresh(char, payload(season("season-mn-1", all: 0)))

      assert_equal 1850, char.reload.mythic_score
    end

    test "a season Raider.io reports before static data knows it is still stored" do
      char = character # no WowSeason rows at all
      refresh(char, payload(season("season-brand-new-1", all: 2100.0)))

      row = char.reload.wow_character_seasons.sole
      assert_equal "season-brand-new-1", row.season_slug
      assert_nil row.wow_season, "unlabelled, but not dropped"
      assert_equal "season-brand-new-1", row.season_name
    end
  end
end
