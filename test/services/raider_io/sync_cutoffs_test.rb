require "test_helper"

module RaiderIo
  class SyncCutoffsTest < ActiveSupport::TestCase
    NOW = Time.utc(2026, 7, 27)

    class FakeClient
      attr_reader :asked

      def initialize(payloads = {}, error: nil)
        @payloads = payloads
        @error = error
        @asked = []
      end

      def mythic_plus_season_cutoffs(region:, season:)
        @asked << { region: region, season: season }
        raise @error if @error && region == "eu"

        @payloads.fetch(region, @payloads[:default])
      end
    end

    def quantile(score, quantile: 0.999, count: 1136, total: 1_135_352)
      { "quantile" => quantile, "quantileMinValue" => score,
        "quantilePopulationCount" => count, "totalPopulationCount" => total }
    end

    def payload(p999: 4156.67, p990: 3896.39, hero: 2497.64)
      { "cutoffs" => {
        "p999" => { "all" => quantile(p999),
                    "horde" => quantile(4022.79, count: 563, total: 562_818),
                    "alliance" => quantile(4205.96, count: 574, total: 572_534) },
        "p990" => { "all" => quantile(p990, quantile: 0.99, count: 11_354) },
        "keystoneHero" => { "all" => quantile(hero, quantile: 0.506, count: 574_489) },
        # allTimed* nests its factions one level deeper and is deliberately
        # skipped; it must not blow up the parse.
        "allTimed20" => { "score" => 3880, "cutoffs" => { "all" => quantile(3880) } },
        "bracketDungeonLevels" => [ 29, 28 ],
        "isRemappedSeason" => true
      } }
    end

    def seed_season!
      WowSeason.create!(slug: "season-mn-1", short_name: "MN1", ranked: true,
                        starts_at: Time.utc(2026, 3, 24), ends_at: Time.utc(2026, 12, 16))
      # The next season is announced with a future start — `live` must not pick it.
      WowSeason.create!(slug: "season-mn-2", short_name: "MN2", ranked: true,
                        starts_at: Time.utc(2026, 12, 16), ends_at: Time.utc(2030, 1, 1))
    end

    def sync(client, regions: %w[us])
      SyncCutoffs.call(client: client, regions: regions, now: NOW)
    end

    test "picks the season actually being played, not the announced one" do
      seed_season!
      client = FakeClient.new({ default: payload })
      result = sync(client)

      assert_equal "season-mn-1", result.season
      assert_equal [ { region: "us", season: "season-mn-1" } ], client.asked
    end

    test "records percentiles and named title tiers with their populations" do
      seed_season!
      sync(FakeClient.new({ default: payload }))

      top = WowMythicPlusCutoff.latest_for(season_slug: "season-mn-1", region: "us", quantile_key: "p999")
      assert_equal 4157, top.score
      assert_equal "top 0.1%", top.label
      assert_equal "1,136 of 1,135,352", top.population_summary
      assert_equal "top 1%", WowMythicPlusCutoff.latest_for(season_slug: "season-mn-1", region: "us",
                                                           quantile_key: "p990").label
      assert WowMythicPlusCutoff.title_tiers.exists?(quantile_key: "keystoneHero")
    end

    # Not cosmetic: measured live, US Horde needed 4023 for top 0.1% and
    # Alliance 4206.
    test "keeps the faction split" do
      seed_season!
      sync(FakeClient.new({ default: payload }))

      horde = WowMythicPlusCutoff.latest_for(season_slug: "season-mn-1", region: "us",
                                            quantile_key: "p999", faction: "horde")
      alliance = WowMythicPlusCutoff.latest_for(season_slug: "season-mn-1", region: "us",
                                               quantile_key: "p999", faction: "alliance")
      assert_equal 4023, horde.score
      assert_equal 4206, alliance.score
    end

    test "regions are independent ladders" do
      seed_season!
      sync(FakeClient.new({ "us" => payload(p999: 4156.67), "eu" => payload(p999: 4184.18) }),
           regions: %w[us eu])

      assert_equal 4157, WowMythicPlusCutoff.latest_for(season_slug: "season-mn-1", region: "us",
                                                       quantile_key: "p999").score
      assert_equal 4184, WowMythicPlusCutoff.latest_for(season_slug: "season-mn-1", region: "eu",
                                                       quantile_key: "p999").score
    end

    # The bar drifts all season and that movement is the data.
    test "a moved cutoff adds a row rather than overwriting" do
      seed_season!
      sync(FakeClient.new({ default: payload(p999: 4156.67) }))
      result = sync(FakeClient.new({ default: payload(p999: 4201.5) }))

      assert_equal 1, result.recorded, "only the change counts"
      assert_equal 4202, WowMythicPlusCutoff.latest_for(season_slug: "season-mn-1", region: "us",
                                                       quantile_key: "p999").score
      assert_equal 2, WowMythicPlusCutoff.where(quantile_key: "p999", faction: "all").count
    end

    test "an unchanged cutoff costs no new row" do
      seed_season!
      sync(FakeClient.new({ default: payload }))
      result = sync(FakeClient.new({ default: payload }))

      assert_equal 0, result.recorded
    end

    # Different shape (factions nested under "cutoffs") — must be ignored
    # cleanly rather than parsed into nonsense.
    test "allTimed entries are skipped without breaking the parse" do
      seed_season!
      sync(FakeClient.new({ default: payload }))

      assert_not WowMythicPlusCutoff.exists?(quantile_key: "allTimed20")
      assert WowMythicPlusCutoff.exists?(quantile_key: "p999"), "the rest still landed"
    end

    test "one region failing does not cost the others" do
      seed_season!
      result = sync(FakeClient.new({ default: payload }, error: Client::RateLimited),
                    regions: %w[us eu])

      assert_equal 1, result.regions
      assert WowMythicPlusCutoff.for_region("us").any?
      assert_empty WowMythicPlusCutoff.for_region("eu")
    end

    test "no live season means nothing is fetched" do
      client = FakeClient.new({ default: payload })
      result = sync(client)

      assert_nil result.season
      assert_empty client.asked
      assert_equal 0, WowMythicPlusCutoff.count
    end

    test "an empty payload is tolerated" do
      seed_season!
      result = sync(FakeClient.new({ default: { "cutoffs" => nil } }))

      assert_equal 0, result.recorded
    end
  end
end
