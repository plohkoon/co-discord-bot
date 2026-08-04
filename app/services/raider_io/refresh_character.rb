module RaiderIo
  # Layer Raider.io's view of a character on top of Blizzard's, and build up
  # their history as it goes.
  #
  # The caching rule that shapes this: **a finished season's score never
  # changes.** So every refresh asks for the live season plus any *ended*
  # seasons we don't have a row for yet — Raider.io lets several ride in one
  # request, so a character's entire Mythic+ history costs one call and is then
  # never fetched again. Steady state is one request returning one live season.
  #
  # Deliberately supplementary: a character with no Raider.io data is still a
  # complete character, so callers treat this as best-effort (see
  # WowCharacterRefreshJob).
  class RefreshCharacter
    # :refreshed — data updated
    # :unknown   — Raider.io has never crawled this character (ordinary for
    #              alts; not an error)
    Result = Struct.new(:character, :status, :seasons_fetched, keyword_init: true) do
      def ok? = status == :refreshed
    end

    ROLES = WowCharacterSeason::ROLES

    # How many past seasons to backfill per request. Chaining is what makes the
    # backfill cheap, but the URL can't grow forever — anything left over is
    # picked up by the next refresh, and once history is complete this is 0.
    BACKFILL_LIMIT = 8

    def self.call(...) = new(...).call

    def initialize(character, client: nil, now: Time.current)
      @character = character
      @client = client || Client.new
      @now = now
    end

    def call
      backfill = missing_season_slugs
      payload = @client.character_profile(
        region: @character.region, realm: @character.realm_slug, name: @character.name,
        fields: fields_for(backfill)
      )

      seasons = store_seasons(payload)
      store_raids(payload)
      store_character(payload, backfill)

      Result.new(character: @character, status: :refreshed, seasons_fetched: seasons)
    rescue Client::NotFound
      # Raider.io only knows characters it has crawled — plenty of real alts
      # have no profile. Stamp the timestamp so the sweep doesn't re-ask until
      # the next staleness window.
      @character.update!(raider_io_refreshed_at: @now)
      Result.new(character: @character, status: :unknown, seasons_fetched: 0)
    end

    private

    def fields_for(backfill)
      [ Client.season_field("current", backfill), "raid_progression", "gear" ]
    end

    # Ended, ranked seasons with no row yet. An ended season is immutable, so a
    # row we already hold is never re-requested; the live season rides along as
    # `current` regardless.
    def missing_season_slugs
      have = @character.wow_character_seasons.pluck(:season_slug)
      WowSeason.ranked.ended(@now).newest_first
               .where.not(slug: have)
               .limit(BACKFILL_LIMIT)
               .pluck(:slug)
    end

    # `mythic_plus_scores_by_season` is an ARRAY of season objects, not a hash
    # keyed by season — even a single `:current` comes back wrapped in one.
    def store_seasons(payload)
      Array(payload["mythic_plus_scores_by_season"]).count do |raw|
        slug = raw["season"].presence or next false

        scores = raw["scores"] || {}
        row = @character.wow_character_seasons.find_or_initialize_by(season_slug: slug)
        row.assign_attributes(
          score_all: scores["all"], score_tank: scores["tank"],
          score_healer: scores["healer"], score_dps: scores["dps"],
          fetched_at: @now
        )
        row.save!
      end
    end

    # Raider.io returns a row for every raid in the expansion, including ones
    # the character has never entered (empty summary, all counts zero). Those
    # are stored too — "0/8 attempted" is a real answer for a recruiter, and it
    # keeps the row ready for when they do start.
    def store_raids(payload)
      Hash(payload["raid_progression"]).each do |slug, data|
        next unless data.is_a?(Hash)

        row = @character.wow_character_raids.find_or_initialize_by(raid_slug: slug)
        row.assign_attributes(
          summary: data["summary"].to_s.strip.presence,
          total_bosses: data["total_bosses"],
          normal_bosses_killed: data["normal_bosses_killed"].to_i,
          heroic_bosses_killed: data["heroic_bosses_killed"].to_i,
          mythic_bosses_killed: data["mythic_bosses_killed"].to_i,
          fetched_at: @now
        )
        row.save!
      end
    end

    # The character row keeps a denormalised copy of the *live* season's score
    # and the current role, so listing a team by score stays a single-table
    # query instead of a join per row.
    #
    # The live season is found by elimination rather than by position: with a
    # backfill in flight the response holds several seasons, and Raider.io
    # doesn't promise `current` comes back first. Everything in `backfill` is by
    # definition an ended season, so whatever isn't in it is the live one.
    def store_character(payload, backfill)
      live = Array(payload["mythic_plus_scores_by_season"])
             .find { |season| backfill.exclude?(season["season"]) }
      @character.update!(
        raider_io_role: payload["active_spec_role"].presence&.downcase,
        raider_io_score: live&.dig("scores", "all"),
        raider_io_refreshed_at: @now
      )
    end
  end
end
