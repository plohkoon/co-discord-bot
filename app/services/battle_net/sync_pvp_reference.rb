module BattleNet
  # Populate the PvP reference tables: seasons, rating tiers, and title cutoffs.
  #
  # Cutoffs are the reason this exists. A PvP rating means nothing on its own —
  # in season 41 the same Shuffle title needed 2205 on one spec and 2998 on
  # another — and the bar drifts all season as the ladder fills. Recording the
  # movement is what makes a stored rating interpretable afterwards.
  #
  # Everything here is app-token game data: no user consent, no per-character
  # cost. Cheap enough to run daily, which is roughly how often cutoffs move.
  class SyncPvpReference
    Result = Struct.new(:seasons, :tiers, :cutoffs, keyword_init: true)

    def self.call(...) = new(...).call

    def initialize(client: nil, region: Client::DEFAULT_REGION, now: Time.current)
      @client = client || Client.app(region: region)
      @now = now
    end

    def call
      seasons = sync_seasons
      tiers = sync_tiers
      cutoffs = sync_cutoffs(WowPvpSeason.current&.blizzard_id)
      Rails.logger.info("[pvp] reference: #{seasons} seasons, #{tiers} tiers, #{cutoffs} cutoff changes")
      Result.new(seasons: seasons, tiers: tiers, cutoffs: cutoffs)
    end

    private

    def sync_seasons
      index = @client.pvp_season_index
      current_id = index.dig("current_pvp_season", "id")

      count = Array(index["seasons"]).count do |raw|
        id = raw["id"] or next false

        season = WowPvpSeason.find_or_initialize_by(blizzard_id: id)
        # Only the current season is worth a detail request; the rest never
        # change and most already have their name.
        season.assign_attributes(details_for(id, current_id))
        season.assign_attributes(current: id == current_id, synced_at: @now)
        season.save!
      end

      # Exactly one season is current; a rollover must clear the old flag.
      WowPvpSeason.where.not(blizzard_id: current_id).update_all(current: false) if current_id
      count
    end

    def details_for(id, current_id)
      return {} unless id == current_id || WowPvpSeason.find_by(blizzard_id: id)&.name.blank?

      detail = @client.pvp_season(id)
      { name: detail["season_name"], starts_at: epoch_ms(detail["season_start_timestamp"]) }
    rescue Client::Error
      {}
    end

    def sync_tiers
      Array(@client.pvp_tier_index["tiers"]).count do |raw|
        id = raw["id"] or next false
        # The index carries only id + name; min_rating needs the detail call.
        detail = begin
          @client.pvp_tier(id)
        rescue Client::Error
          nil
        end

        tier = WowPvpTier.find_or_initialize_by(blizzard_id: id)
        tier.assign_attributes(
          name: detail&.dig("name") || raw["name"],
          min_rating: detail&.dig("min_rating"),
          max_rating: detail&.dig("max_rating"),
          bracket_type: detail&.dig("bracket", "type"),
          synced_at: @now
        )
        tier.save!
      end
    end

    # A changed cutoff is a new row, so the unique index does the deduping and
    # an unchanged bar costs nothing.
    def sync_cutoffs(season_id)
      return 0 if season_id.blank?

      Array(@client.pvp_rewards(season_id)["rewards"]).count do |raw|
        cutoff = raw["rating_cutoff"] or next false
        bracket = raw.dig("bracket", "type") or next false

        row = WowPvpCutoff.find_or_initialize_by(
          season_id: season_id, bracket_type: bracket,
          specialization_id: raw.dig("specialization", "id"), rating_cutoff: cutoff
        )
        next false if row.persisted? # bar hasn't moved

        row.assign_attributes(
          specialization_name: raw.dig("specialization", "name"),
          achievement_name: raw.dig("achievement", "name"),
          captured_at: @now
        )
        row.save!
      end
    end

    def epoch_ms(value) = value.present? ? Time.zone.at(value.to_i / 1000) : nil
  end
end
