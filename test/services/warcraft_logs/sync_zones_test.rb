require "test_helper"

module WarcraftLogs
  class SyncZonesTest < ActiveSupport::TestCase
    class FakeClient
      def initialize(zones) = @zones = zones
      def zones(expansion_id: nil) = @zones
    end

    def zone(id, name:, frozen:, expansion: 11, difficulties: [ 3, 4, 5 ], encounters: [])
      { "id" => id, "name" => name, "frozen" => frozen,
        "expansion" => { "id" => expansion, "name" => "Expansion #{expansion}" },
        "difficulties" => difficulties.map { |d| { "id" => d, "name" => "D#{d}" } },
        "encounters" => encounters }
    end

    test "stores zones and maps Warcraft Logs' frozen onto closed" do
      SyncZones.call(client: FakeClient.new([
        zone(45, name: "MN Tier 1", frozen: false),
        zone(42, name: "TWW Tier 3", frozen: true)
      ]))

      live = WarcraftLogsZone.find_by(wcl_id: 45)
      assert_equal "MN Tier 1", live.name
      assert_equal 11, live.expansion_id
      assert_not live.closed?
      assert WarcraftLogsZone.find_by(wcl_id: 42).closed?
    end

    # The whole caching strategy hangs off this partition.
    test "live and closed scopes split the tiers" do
      SyncZones.call(client: FakeClient.new([
        zone(45, name: "Live", frozen: false),
        zone(42, name: "Old", frozen: true),
        zone(38, name: "Older", frozen: true)
      ]))

      assert_equal [ 45 ], WarcraftLogsZone.live.pluck(:wcl_id)
      assert_equal [ 42, 38 ], WarcraftLogsZone.closed.newest_first.pluck(:wcl_id)
    end

    # A tier freezing is the event that stops it being re-fetched, so the sync
    # has to be able to flip it.
    test "a tier that has since closed is updated in place" do
      SyncZones.call(client: FakeClient.new([ zone(45, name: "Tier", frozen: false) ]))
      result = SyncZones.call(client: FakeClient.new([ zone(45, name: "Tier", frozen: true) ]))

      assert_equal 1, WarcraftLogsZone.count
      assert WarcraftLogsZone.sole.closed?
      assert_equal 1, result.closed
    end

    # Raid tiers and M+ seasons arrive in the same list; only their difficulty
    # ids tell them apart.
    test "Mythic+ seasons are classified apart from raid tiers" do
      SyncZones.call(client: FakeClient.new([
        zone(46, name: "VS / DR / MQD", frozen: false),
        zone(47, name: "Mythic+ Season 1", frozen: false, difficulties: [ 10 ])
      ]))

      assert_equal [ 46 ], WarcraftLogsZone.raids.pluck(:wcl_id)
      assert_equal [ 47 ], WarcraftLogsZone.mythic_plus.pluck(:wcl_id)
    end

    # Warcraft Logs publishes journalID but never populates it (0 everywhere,
    # verified live), so the Raider.io join falls back to normalised names.
    test "encounters link to Raider.io by name when journalID is absent" do
      WowEncounter.record!(journal_id: 197_132, name: "Chimaerus the Undreamt God", raid_slug: "tier-mn-1")

      result = SyncZones.call(client: FakeClient.new([
        zone(46, name: "VS / DR / MQD", frozen: false, encounters: [
          # Comma differs from Raider.io's spelling — the exact live mismatch.
          { "id" => 3306, "name" => "Chimaerus, the Undreamt God", "journalID" => 0 }
        ])
      ]))

      assert_equal 1, result.linked
      assert_equal 46, WowEncounter.find_by(journal_id: 197_132).wcl_zone_id
    end

    test "a real journalID is preferred over the name fallback" do
      WowEncounter.record!(journal_id: 197_132, name: "Something Else", raid_slug: "tier-mn-1")

      SyncZones.call(client: FakeClient.new([
        zone(46, name: "Tier", frozen: false,
             encounters: [ { "id" => 1, "name" => "Unrelated", "journalID" => 197_132 } ])
      ]))

      assert_equal 46, WowEncounter.find_by(journal_id: 197_132).wcl_zone_id
    end

    test "an encounter Raider.io has never mentioned is not invented" do
      result = SyncZones.call(client: FakeClient.new([
        zone(46, name: "Tier", frozen: false,
             encounters: [ { "id" => 1, "name" => "Nobody Knows", "journalID" => 0 } ])
      ]))

      assert_equal 0, result.linked
      assert_equal 0, WowEncounter.count
    end

    test "a zone with no id is skipped rather than raising" do
      result = SyncZones.call(client: FakeClient.new([ { "name" => "Broken" },
                                                       zone(45, name: "Fine", frozen: false) ]))

      assert_equal 1, result.zones
      assert_equal [ 45 ], WarcraftLogsZone.pluck(:wcl_id)
    end
  end
end
