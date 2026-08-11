require "test_helper"

module RaiderIo
  class SyncStaticDataTest < ActiveSupport::TestCase
    # Serves per-expansion payloads and raises Unsupported past the newest one,
    # exactly as Raider.io does.
    class FakeClient
      attr_reader :asked

      def initialize(seasons: {}, raids: {})
        @seasons = seasons
        @raids = raids
        @asked = []
      end

      def mythic_plus_static_data(expansion_id:)
        @asked << expansion_id
        payload = @seasons[expansion_id] or raise Client::Unsupported, "unsupported expansion_id"

        { "seasons" => payload }
      end

      def raiding_static_data(expansion_id:)
        { "raids" => @raids.fetch(expansion_id, []) }
      end
    end

    def season(slug, starts: "2026-03-24T15:00:00Z", ends: "2026-12-16T15:00:00Z", name: nil)
      { "slug" => slug, "name" => name || slug.titleize, "short_name" => slug.split("-").last,
        "starts" => { "us" => starts, "eu" => "2026-03-25T04:00:00Z" },
        "ends" => { "us" => ends, "eu" => "2026-12-17T04:00:00Z" } }
    end

    def sync(client, expansions: 9..13)
      SyncStaticData.call(client: client, expansions: expansions)
    end

    test "stores seasons with their start and end times" do
      client = FakeClient.new(seasons: { 9 => [ season("season-mn-1") ] })
      result = sync(client)

      assert_equal 1, result.seasons
      row = WowSeason.sole
      assert_equal "season-mn-1", row.slug
      assert_equal 9, row.expansion_id
      assert_equal Time.utc(2026, 12, 16, 15), row.ends_at
      assert row.synced_at.present?
    end

    # Raider.io mints slugs for events and re-cuts alongside the real ladder.
    # Nobody recruits on those, so they must not be backfilled.
    test "flags only the real ladder seasons as ranked" do
      client = FakeClient.new(seasons: { 9 => [
        season("season-tww-1"), season("season-tww-1-post"),
        season("season-tww-1-break-the-meta"), season("season-df-4-cutoffs"),
        season("season-df-3-meta-vs-meta"), season("season-tww-3-legion-remix")
      ] })
      sync(client)

      assert_equal %w[season-tww-1], WowSeason.ranked.pluck(:slug)
      assert_equal 5, WowSeason.where(ranked: false).count
    end

    test "re-running updates in place rather than duplicating" do
      client = FakeClient.new(seasons: { 9 => [ season("season-mn-1", name: "Old") ] })
      sync(client)
      client2 = FakeClient.new(seasons: { 9 => [ season("season-mn-1", name: "New") ] })
      sync(client2)

      assert_equal 1, WowSeason.count
      assert_equal "New", WowSeason.sole.name
    end

    # Probing expansion ids upward is how the newest one is discovered.
    test "stops probing at the first expansion Raider.io does not publish" do
      client = FakeClient.new(seasons: { 9 => [ season("season-df-1") ], 10 => [ season("season-tww-1") ] })
      sync(client)

      assert_equal [ 9, 10, 11 ], client.asked, "stops at the first Unsupported, not the range ceiling"
      assert_equal 2, WowSeason.count
    end

    test "stores raid tiers with their boss counts" do
      client = FakeClient.new(
        seasons: { 9 => [] },
        raids: { 9 => [ { "slug" => "tier-mn-1", "name" => "MN Tier 1", "short_name" => "VS/DR/MQD",
                          "encounters" => Array.new(9) { |i| { "id" => i } } } ] }
      )
      result = sync(client)

      assert_equal 1, result.raids
      raid = WowRaid.sole
      assert_equal 9, raid.boss_count
      assert_equal "MN Tier 1", raid.display_name
    end

    test "a season with unparseable dates is still recorded" do
      client = FakeClient.new(seasons: { 9 => [ season("season-mn-1", ends: "not a date") ] })
      sync(client)

      assert_nil WowSeason.sole.ends_at
      assert_not WowSeason.sole.ended?, "an unknown end date is not an ended season"
    end
  end
end
