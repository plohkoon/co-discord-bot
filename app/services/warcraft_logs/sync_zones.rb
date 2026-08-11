module WarcraftLogs
  # Populate the raid-zone reference table.
  #
  # Same role as RaiderIo::SyncStaticData: it has to run before character
  # refreshes can be cheap, because a zone's closed flag is what proves a
  # tier's parses are final and never need fetching again.
  #
  # One GraphQL query for all zones (Warcraft Logs returns every expansion when
  # expansion_id is omitted), so this is cheap enough to run weekly.
  class SyncZones
    Result = Struct.new(:zones, :closed, :linked, keyword_init: true)

    def self.call(...) = new(...).call

    def initialize(client: Client.new)
      @client = client
    end

    def call
      @linked = 0
      rows = Array(@client.zones)
      count = rows.count { |raw| store(raw) }
      closed = WarcraftLogsZone.closed.count
      Rails.logger.info("[wcl] zones: #{count} synced, #{closed} closed, #{@linked} encounters linked to Raider.io")
      Result.new(zones: count, closed: closed, linked: @linked)
    end

    private

    def store(raw)
      id = raw["id"] or return false

      zone = WarcraftLogsZone.find_or_initialize_by(wcl_id: id)
      zone.assign_attributes(
        name: raw["name"],
        expansion_id: raw.dig("expansion", "id"),
        expansion_name: raw.dig("expansion", "name"),
        # Warcraft Logs' `frozen` becomes our `closed`. A zone it hasn't
        # frozen is either the live tier or one still taking logs; either way
        # it stays refreshable.
        closed: !!raw["frozen"],
        # Raid tier or Mythic+ season — see WarcraftLogsZone.kind_from_difficulties.
        kind: WarcraftLogsZone.kind_from_difficulties(
          Array(raw["difficulties"]).map { |d| d["id"] }
        ),
        synced_at: Time.current
      )
      zone.save!
      @linked += record_encounters(raw, id)
      true
    end

    # The other half of the Raider.io ↔ Warcraft Logs join.
    #
    # This ANNOTATES encounters Raider.io has already recorded rather than
    # creating its own: Warcraft Logs publishes `journalID` but never populates
    # it (verified — 0 across every zone, current and years old), so there is no
    # id to key a new row on. `link_warcraft_logs!` prefers the journal id when
    # it's real and falls back to a normalised boss name, which matched 9/9 in
    # the live tier.
    def record_encounters(raw, wcl_zone_id)
      Array(raw["encounters"]).count do |encounter|
        WowEncounter.link_warcraft_logs!(
          name: encounter["name"], journal_id: encounter["journalID"], wcl_zone_id: wcl_zone_id
        )
      end
    end
  end
end
