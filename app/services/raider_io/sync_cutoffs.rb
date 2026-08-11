module RaiderIo
  # Record the Mythic+ score percentiles for the live season, per region.
  #
  # Separate from SyncStaticData and on a faster cadence because these move
  # continuously as the ladder fills, whereas seasons and raids change once an
  # expansion. Blizzard publishes no M+ cutoffs at all, so this is the only
  # source — and a bar not captured while it was live can't be reconstructed.
  #
  # A changed value writes a new row; an unchanged one costs nothing.
  class SyncCutoffs
    Result = Struct.new(:season, :regions, :recorded, keyword_init: true)

    # us/eu/kr/tw ladders are independent — measured: US top 0.1% 4156.67 vs
    # EU 4184.18 against very different population sizes.
    REGIONS = %w[us eu kr tw].freeze

    # Raider.io nests every quantile the same way except allTimed*, which wraps
    # its factions under a "cutoffs" key. Those are a different kind of
    # benchmark (score to have timed everything at +N) and are skipped — see
    # TODOS.
    QUANTILE_KEYS = (WowMythicPlusCutoff::PERCENTILES + WowMythicPlusCutoff::TITLE_TIERS).freeze

    def self.call(...) = new(...).call

    def initialize(client: Client.new, regions: REGIONS, season: nil, now: Time.current)
      @client = client
      @regions = Array(regions)
      @season = season
      @now = now
    end

    def call
      slug = @season || WowSeason.live&.slug
      return Result.new(season: nil, regions: 0, recorded: 0) if slug.blank?

      regions = 0
      recorded = 0
      @regions.each do |region|
        recorded += sync_region(slug, region)
        regions += 1
      rescue Client::Error => e
        # One region's ladder being unavailable shouldn't cost the others.
        Rails.logger.warn("[raider.io] cutoffs failed for #{region}: #{e.class}: #{e.message}")
      end

      Rails.logger.info("[raider.io] cutoffs #{slug}: #{recorded} changes across #{regions} regions")
      Result.new(season: slug, regions: regions, recorded: recorded)
    end

    private

    def sync_region(slug, region)
      # `season` is documented as optional but omitting it 500s, so it is always
      # sent explicitly.
      payload = @client.mythic_plus_season_cutoffs(region: region, season: slug)
      cutoffs = payload&.dig("cutoffs") or return 0

      QUANTILE_KEYS.sum do |key|
        entry = cutoffs[key]
        next 0 unless entry.is_a?(Hash)

        WowMythicPlusCutoff::FACTIONS.count do |faction|
          store(slug, region, faction, key, entry[faction])
        end
      end
    end

    def store(slug, region, faction, key, data)
      return false unless data.is_a?(Hash)

      score = data["quantileMinValue"] or return false

      row = WowMythicPlusCutoff.find_or_initialize_by(
        season_slug: slug, region: region, faction: faction,
        quantile_key: key, min_score: score
      )
      return false if row.persisted? # bar hasn't moved

      row.assign_attributes(
        quantile: data["quantile"],
        population_count: data["quantilePopulationCount"],
        total_population: data["totalPopulationCount"],
        captured_at: @now
      )
      row.save!
    end
  end
end
