module BattleNet
  # Pull a character's PvP ratings for the current season.
  #
  # Two things make this different from the PvE refreshes:
  #
  # 1. **There is no history to backfill.** Blizzard answers the character
  #    bracket endpoint for the current season only, so a rating not recorded
  #    while it's live is gone permanently. That inverts the Raider.io rule —
  #    the live season is not just the cheap thing to refresh, it's the *only*
  #    thing obtainable, and every refresh is the last chance to capture it.
  #
  # 2. **A character has many ratings, not one.** 2v2/3v3/rbg carry one each,
  #    but Solo Shuffle and Blitz are rated per specialisation. `pvp-summary`
  #    lists exactly which brackets the character has played, so the fan-out is
  #    read from Blizzard rather than guessed — one request to find out, then
  #    one per bracket.
  #
  # A character with no rated play costs a single request and stores nothing.
  class RefreshCharacterPvp
    Result = Struct.new(:character, :status, :brackets_fetched, keyword_init: true) do
      def ok? = status == :refreshed
    end

    def self.call(...) = new(...).call

    def initialize(character, client: nil, now: Time.current)
      @character = character
      @client = client || Client.app(region: character.region)
      @now = now
    end

    def call
      summary = @client.pvp_summary(@character.realm_slug, @character.name)
      store_summary(summary)

      season_id = WowPvpSeason.current&.blizzard_id
      brackets = bracket_slugs(summary)
      return done(0) if season_id.blank? || brackets.empty?

      fetched = brackets.count { |slug| store_bracket(season_id, slug) }
      done(fetched)
    rescue Client::NotFound
      # Blizzard doesn't know the character (renamed/transferred) — the PvE
      # refresh already records that; nothing extra to do here.
      Result.new(character: @character, status: :missing, brackets_fetched: 0)
    end

    private

    def done(count)
      @character.update!(pvp_refreshed_at: @now)
      Result.new(character: @character, status: :refreshed, brackets_fetched: count)
    end

    def store_summary(summary)
      @character.assign_attributes(
        honor_level: summary["honor_level"],
        honorable_kills: summary["honorable_kills"]
      )
      @character.save! if @character.changed?
    end

    # `brackets` is a list of link objects; the slug is the tail of the href.
    #   .../pvp-bracket/shuffle-mage-frost?namespace=profile-us
    def bracket_slugs(summary)
      Array(summary["brackets"]).filter_map do |entry|
        entry["href"].to_s[%r{pvp-bracket/([^?]+)}, 1]
      end.uniq
    end

    def store_bracket(season_id, slug)
      payload = @client.pvp_bracket(@character.realm_slug, @character.name, slug)
      return false if payload.blank?

      # Trust the season the payload reports over the one we assumed — a season
      # rollover mid-sweep would otherwise file a rating under the wrong one.
      season = payload.dig("season", "id") || season_id
      type, spec = WowCharacterPvpRating.parse_bracket(slug)

      row = @character.wow_character_pvp_ratings.find_or_initialize_by(
        season_id: season, bracket: slug
      )
      row.assign_attributes(
        bracket_type: type, spec_slug: spec,
        rating: payload["rating"], tier_id: payload.dig("tier", "id"),
        played: payload.dig("season_match_statistics", "played").to_i,
        won: payload.dig("season_match_statistics", "won").to_i,
        lost: payload.dig("season_match_statistics", "lost").to_i,
        weekly_played: payload.dig("weekly_match_statistics", "played").to_i,
        weekly_won: payload.dig("weekly_match_statistics", "won").to_i,
        weekly_lost: payload.dig("weekly_match_statistics", "lost").to_i,
        fetched_at: @now
      )
      row.save!
    rescue Client::NotFound
      # Listed in the summary but not queryable — skip rather than fail the lot.
      false
    end
  end
end
