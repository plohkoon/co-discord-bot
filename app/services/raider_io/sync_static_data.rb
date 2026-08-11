module RaiderIo
  # Populate the shared reference tables: which Mythic+ seasons and raid tiers
  # exist, what they're called, and when seasons start and end.
  #
  # This is what lets the refresh loop be cheap. Knowing a season's `ends_at`
  # is what tells us its scores are frozen, so a character's row for it is
  # fetched once and never again (see RaiderIo::RefreshCharacter). Without it
  # we'd have to re-fetch every season every time to find out nothing changed.
  #
  # Slow-moving by nature — a weekly run is plenty, and a new expansion is the
  # only thing that really changes the answer.
  class SyncStaticData
    # Raider.io indexes static data by expansion. There's no "list expansions"
    # endpoint, so this is a range: 9 = Dragonflight, 10 = The War Within,
    # 11 = Midnight. Extend the ceiling when an expansion ships; unknown ids
    # answer with no seasons rather than an error, so overshooting is free.
    EXPANSIONS = (9..13).freeze

    Result = Struct.new(:seasons, :raids, keyword_init: true)

    def self.call(...) = new(...).call

    def initialize(client: Client.new, expansions: EXPANSIONS)
      @client = client
      @expansions = expansions
    end

    def call
      seasons = 0
      raids = 0
      @expansions.each do |id|
        # Probing upward is how the newest expansion is discovered; Raider.io
        # answers an id it doesn't publish with Unsupported, which ends the
        # loop rather than failing the sync.
        seasons += sync_seasons(id)
        raids += sync_raids(id)
      rescue Client::Unsupported
        break
      end

      Rails.logger.info("[raider.io] static data: #{seasons} seasons, #{raids} raids")
      Result.new(seasons: seasons, raids: raids)
    end

    private

    def sync_seasons(expansion_id)
      payload = @client.mythic_plus_static_data(expansion_id: expansion_id)
      Array(payload&.dig("seasons")).count do |raw|
        slug = raw["slug"].presence or next false

        season = WowSeason.find_or_initialize_by(slug: slug)
        season.assign_attributes(
          name: raw["name"], short_name: raw["short_name"], expansion_id: expansion_id,
          starts_at: region_time(raw["starts"]), ends_at: region_time(raw["ends"]),
          ranked: WowSeason.ranked_slug?(slug), synced_at: Time.current
        )
        season.save!
      end
    rescue Client::NotFound
      0 # expansion id Raider.io doesn't publish
    end

    def sync_raids(expansion_id)
      payload = @client.raiding_static_data(expansion_id: expansion_id)
      Array(payload&.dig("raids")).count do |raw|
        slug = raw["slug"].presence or next false

        raid = WowRaid.find_or_initialize_by(slug: slug)
        raid.assign_attributes(
          name: raw["name"], short_name: raw["short_name"], expansion_id: expansion_id,
          boss_count: Array(raw["encounters"]).size.presence, synced_at: Time.current
        )
        raid.save!
        record_encounters(raw, slug)
        true
      end
    rescue Client::NotFound
      0
    end

    # Raider.io's encounter `id` IS Blizzard's journal encounter id, which
    # Warcraft Logs also publishes (as `journalID`). Recording them here is what
    # makes the two services' raid data joinable — see WowEncounter.
    def record_encounters(raw, raid_slug)
      Array(raw["encounters"]).each do |encounter|
        WowEncounter.record!(
          journal_id: encounter["id"], name: encounter["name"], raid_slug: raid_slug
        )
      end
    end

    # Seasons open and close a few hours apart per region. Only "has this ended"
    # is ever asked, so US stands in for all of them rather than growing four
    # columns to answer a question nobody asks that precisely.
    def region_time(times)
      value = times.is_a?(Hash) ? (times["us"] || times.values.first) : times
      Time.zone.parse(value.to_s)
    rescue ArgumentError, TypeError
      nil
    end
  end
end
