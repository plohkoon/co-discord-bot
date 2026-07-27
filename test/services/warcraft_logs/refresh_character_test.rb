require "test_helper"

module WarcraftLogs
  class RefreshCharacterTest < ActiveSupport::TestCase
    NOW = Time.utc(2026, 7, 27)

    class FakeClient
      attr_reader :calls

      # `responses` maps zone id => payload (or an exception class to raise).
      def initialize(responses)
        @responses = responses
        @calls = []
      end

      def character_zone_rankings(name:, server_slug:, region:, zone_id: nil, difficulty: nil, metric: "default")
        @calls << { name: name, server_slug: server_slug, region: region,
                    zone_id: zone_id, difficulty: difficulty }
        payload = @responses.fetch(zone_id, @responses[:default])
        raise payload if payload.is_a?(Class) && payload <= StandardError

        payload
      end

      def zones_asked = calls.map { |c| c[:zone_id] }
    end

    # Mirrors the zoneRankings JSON scalar: allStars is an array, kills are
    # per-encounter, and the payload states its own difficulty.
    def rankings(difficulty: 5, best: 91.2, median: 84.7, kills: [ 8, 6 ], spec: "Blood")
      { "difficulty" => difficulty,
        "bestPerformanceAverage" => best,
        "medianPerformanceAverage" => median,
        "metric" => "dps",
        "bestSpec" => spec,
        "allStars" => [ { "points" => 412.5, "rank" => 1203, "rankPercent" => 96.4, "spec" => spec } ],
        "rankings" => kills.map { |k| { "encounter" => { "id" => k, "name" => "Boss #{k}" },
                                        "totalKills" => k } } }
    end

    def character_payload(zone_rankings, id: 55_501)
      { "id" => id, "name" => "Jörmûngandr", "classID" => 1, "hidden" => false,
        "server" => { "slug" => "sargeras", "region" => { "slug" => "us" } },
        "zoneRankings" => zone_rankings }
    end

    def seed_zones!
      WarcraftLogsZone.create!(wcl_id: 45, name: "MN Tier 1", expansion_id: 11, closed: false)
      WarcraftLogsZone.create!(wcl_id: 42, name: "TWW Tier 3", expansion_id: 10, closed: true)
      WarcraftLogsZone.create!(wcl_id: 38, name: "TWW Tier 2", expansion_id: 10, closed: true)
    end

    # Warcraft Logs lists M+ seasons alongside raid tiers in the same collection.
    def seed_mythic_plus_zone!
      WarcraftLogsZone.create!(wcl_id: 47, name: "Mythic+ Season 1", expansion_id: 11,
                               closed: false, kind: WarcraftLogsZone::MYTHIC_PLUS)
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

    def refresh(char, responses)
      client = FakeClient.new(responses)
      [ RefreshCharacter.call(char, client: client, now: NOW), client ]
    end

    # --- The caching rule ---

    test "fetches the live tier plus one frozen tier to backfill" do
      seed_zones!
      _result, client = refresh(character, default: character_payload(rankings))

      assert_equal [ 45, 42 ], client.zones_asked, "live tier first, then the newest gap"
    end

    # A frozen tier's parses are history — the whole reason this is a table.
    test "a frozen tier already stored is never fetched again" do
      seed_zones!
      char = character
      refresh(char, default: character_payload(rankings))    # gets 45 (live) + 42
      _r, client = refresh(char.reload, default: character_payload(rankings)) # gets 45 + 38

      assert_equal [ 45, 38 ], client.zones_asked, "42 is frozen and already stored"
    end

    test "the live tier is re-fetched every time even though it is stored" do
      seed_zones!
      char = character
      refresh(char, default: character_payload(rankings(median: 70.0)))
      refresh(char.reload, default: character_payload(rankings(median: 84.7)))

      row = char.warcraft_logs_rankings.find_by(wcl_zone_id: 45)
      assert_equal 85, row.median, "updated in place"
      assert_equal 1, char.warcraft_logs_rankings.where(wcl_zone_id: 45).count
    end

    test "backfill finishes and then steady state is the live tier alone" do
      seed_zones!
      char = character
      3.times { refresh(char.reload, default: character_payload(rankings)) }
      _r, client = refresh(char.reload, default: character_payload(rankings))

      assert_equal [ 45 ], client.zones_asked, "all frozen tiers are stored; nothing left to backfill"
    end

    # --- What gets stored ---

    test "stores the headline percentiles, all-stars and kill count" do
      seed_zones!
      char = character
      refresh(char, default: character_payload(rankings))

      row = char.warcraft_logs_rankings.find_by(wcl_zone_id: 45)
      assert_equal 91, row.best
      assert_equal 85, row.median
      assert_equal 85, row.headline, "the typical night, not the lucky pull"
      assert_equal 14, row.total_kills, "summed across encounters, which is how WCL reports it"
      assert_equal 412.5, row.all_stars_points.to_f
      assert_equal 96, row.all_stars_rank_percent
      assert_equal "Blood", row.spec_name
      assert_equal 5, row.difficulty
    end

    # A 99 off one kill is a different claim from a 99 off thirty.
    test "the kill count travels with the number" do
      seed_zones!
      char = character
      refresh(char, default: character_payload(rankings(median: 99.0, kills: [ 1 ])))

      assert_equal "99 Mythic (1 kill)", char.warcraft_logs_rankings.find_by(wcl_zone_id: 45).summary
    end

    test "records the stable Warcraft Logs character id" do
      seed_zones!
      char = character
      refresh(char, default: character_payload(rankings, id: 98_765))

      assert_equal 98_765, char.reload.warcraft_logs_id
    end

    # The payload states its own difficulty; someone who later clears a harder
    # one gets a second row rather than overwriting their heroic record.
    test "a harder difficulty adds a row rather than replacing the easier one" do
      seed_zones!
      char = character
      refresh(char, 45 => character_payload(rankings(difficulty: 4, median: 70.0)),
                    default: character_payload(nil))
      refresh(char.reload, 45 => character_payload(rankings(difficulty: 5, median: 88.0)),
                           default: character_payload(nil))

      rows = char.warcraft_logs_rankings.where(wcl_zone_id: 45).order(:difficulty)
      assert_equal [ 4, 5 ], rows.map(&:difficulty)
      assert_equal 5, char.best_ranking.difficulty, "the hardest cleared is the headline"
      assert_equal 88, char.parse
    end

    # M+ rankings are not raid parses, and because M+ is difficulty 10 against
    # mythic raid's 5 an M+ row wins any highest-difficulty comparison — it
    # hijacked the headline parse on live data before this was fixed.
    test "Mythic+ zones are never fetched as raid parses" do
      seed_zones!
      seed_mythic_plus_zone!
      _result, client = refresh(character, default: character_payload(rankings))

      assert_not_includes client.zones_asked, 47
      assert_equal [ 45, 42 ], client.zones_asked
    end

    # Same difficulty, same parse: more kills is the stronger credential.
    test "the headline breaks ties on kill count, not zone id" do
      seed_zones!
      char = character
      refresh(char, 45 => character_payload(rankings(median: 99.0, kills: [ 5 ])),
                    42 => character_payload(rankings(median: 99.0, kills: [ 80, 63 ])),
                    default: character_payload(nil))

      assert_equal 143, char.best_ranking.total_kills,
                   "the nine-boss tier beats the one-boss raid at the same parse"
    end

    # --- Failure modes ---

    test "a character never in a logged raid is recorded, not retried forever" do
      seed_zones!
      char = character
      result, = refresh(char, default: Client::NotFound)

      assert_equal :unknown, result.status
      char.reload
      assert char.logs_missing?
      assert char.warcraft_logs_refreshed_at.present?
      assert_empty char.warcraft_logs_rankings
    end

    test "a character with a profile but no parses in a tier stores nothing for it" do
      seed_zones!
      char = character
      result, = refresh(char, default: character_payload(nil))

      assert result.ok?
      assert_equal 0, result.zones_fetched
      assert_empty char.warcraft_logs_rankings
      assert_not char.reload.logs_missing?, "they exist on WCL, just not in this tier"
    end

    test "rate limiting propagates so the caller can back off" do
      seed_zones!
      assert_raises(Client::RateLimited) { refresh(character, default: Client::RateLimited) }
    end

    test "with no zones synced yet nothing is fetched and no error is raised" do
      char = character
      result, client = refresh(char, default: character_payload(rankings))

      assert result.ok?
      assert_empty client.zones_asked, "the zone sync has to run first"
      assert char.reload.warcraft_logs_refreshed_at.present?
    end

    test "a ranking arriving before its zone is synced is still stored" do
      WarcraftLogsZone.create!(wcl_id: 45, name: "MN Tier 1", expansion_id: 11, closed: false)
      char = character
      refresh(char, default: character_payload(rankings))
      char.warcraft_logs_rankings.first.update!(wcl_zone_id: 999)

      row = char.reload.warcraft_logs_rankings.sole
      assert_nil row.warcraft_logs_zone
      assert_equal "Zone 999", row.zone_name, "unlabelled, but not dropped"
    end
  end
end
