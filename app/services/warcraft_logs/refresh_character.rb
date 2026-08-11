module WarcraftLogs
  # Pull a character's parse percentiles for one raid tier.
  #
  # Cached on the same rule as the Raider.io satellites: **a frozen tier's
  # parses never change**, so a stored ranking for a frozen zone is never
  # fetched again. Steady state is one query for the live tier.
  #
  # Unlike seasons, Warcraft Logs can't return several tiers in one query — the
  # zoneID is a single argument — so history is backfilled one zone per call,
  # oldest gap first, spread across refreshes. That's deliberate: parses are
  # points-metered (3,600/hour) and nobody needs five years of history today.
  #
  # Deliberately supplementary. Most characters have never been in a logged
  # raid, and that's an ordinary answer, not a failure.
  class RefreshCharacter
    # :refreshed — data updated
    # :unknown   — Warcraft Logs has never seen this character
    Result = Struct.new(:character, :status, :zones_fetched, keyword_init: true) do
      def ok? = status == :refreshed
    end

    # Zones to backfill per refresh, on top of the live tier. Each is its own
    # query, so this is the points budget knob.
    BACKFILL_LIMIT = 1

    def self.call(...) = new(...).call

    def initialize(character, client: nil, now: Time.current)
      @character = character
      @client = client || Client.new
      @now = now
    end

    def call
      zones = zones_to_fetch
      return skipped if zones.empty?

      fetched = 0
      zones.each do |zone|
        fetched += 1 if fetch_zone(zone)
      end

      @character.update!(warcraft_logs_refreshed_at: @now, warcraft_logs_missing_at: nil)
      Result.new(character: @character, status: :refreshed, zones_fetched: fetched)
    rescue Client::NotFound
      # Never been in a logged raid. Extremely common — most alts, and plenty of
      # mains. Stamp it so the sweep stops asking.
      @character.update!(warcraft_logs_missing_at: @now, warcraft_logs_refreshed_at: @now)
      Result.new(character: @character, status: :unknown, zones_fetched: 0)
    end

    private

    def skipped
      @character.update!(warcraft_logs_refreshed_at: @now)
      Result.new(character: @character, status: :refreshed, zones_fetched: 0)
    end

    # The live tier every time, plus at most one frozen tier we have no ranking
    # for yet. Frozen tiers already stored are never revisited.
    #
    # **Raid zones only.** Warcraft Logs lists Mythic+ seasons in the same
    # collection, and a M+ ranking is not a raid parse — worse, M+ uses
    # difficulty 10 against mythic raid's 5, so an M+ row wins any
    # highest-difficulty comparison and hijacks the headline parse. Raider.io
    # score is the M+ metric anyway.
    def zones_to_fetch
      live = WarcraftLogsZone.raids.live.newest_first.to_a
      have = @character.warcraft_logs_rankings.pluck(:wcl_zone_id).uniq
      backfill = WarcraftLogsZone.raids.closed.newest_first
                                 .where.not(wcl_id: have)
                                 .limit(BACKFILL_LIMIT)
                                 .to_a
      (live + backfill).uniq(&:wcl_id)
    end

    # No difficulty is requested. zoneRankings answers for exactly one, and left
    # to itself Warcraft Logs picks the hardest the character has cleared —
    # which is the one a recruiter wants anyway. Asking per difficulty would
    # double the points cost to learn the same thing.
    def fetch_zone(zone)
      payload = @client.character_zone_rankings(
        name: @character.name, server_slug: @character.realm_slug,
        region: @character.region, zone_id: zone.wcl_id
      )
      return false if payload.blank?

      store_identity(payload)

      rankings = payload["zoneRankings"]
      return false if rankings.blank?

      store_ranking(zone, rankings)
    end

    # Warcraft Logs' character id is stable across renames, unlike the
    # name+server lookup we need to find them the first time.
    def store_identity(payload)
      id = payload["id"] or return

      @character.update!(warcraft_logs_id: id) if @character.warcraft_logs_id != id
    end

    # The payload states which difficulty it answered for; that's authoritative.
    # Someone who later clears a harder difficulty gets a second row rather than
    # overwriting the first — their heroic tier is still part of their record.
    def store_ranking(zone, rankings)
      difficulty = rankings["difficulty"] or return false

      row = @character.warcraft_logs_rankings.find_or_initialize_by(
        wcl_zone_id: zone.wcl_id, difficulty: difficulty
      )
      row.assign_attributes(attributes_from(rankings).merge(fetched_at: @now))
      row.save!
    end

    def attributes_from(rankings)
      per_encounter = Array(rankings["rankings"])
      {
        best_performance_average: rankings["bestPerformanceAverage"],
        median_performance_average: rankings["medianPerformanceAverage"],
        all_stars_points: all_stars(rankings, "points"),
        all_stars_rank: all_stars(rankings, "rank"),
        all_stars_rank_percent: all_stars(rankings, "rankPercent")&.round,
        # Warcraft Logs reports kills per encounter, not per zone.
        total_kills: per_encounter.sum { |e| e["totalKills"].to_i },
        spec_name: rankings["bestSpec"] || all_stars(rankings, "spec"),
        metric: rankings["metric"]
      }
    end

    # `allStars` is an array with one entry per PARTITION (a tier's sub-periods),
    # not per spec — verified live: three entries, all the same spec. It is
    # ordered best-first, so the first entry is the character's peak standing.
    def all_stars(rankings, key)
      entry = Array(rankings["allStars"]).first
      entry.is_a?(Hash) ? entry[key] : nil
    end
  end
end
