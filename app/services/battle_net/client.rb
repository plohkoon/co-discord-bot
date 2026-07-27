require "net/http"

module BattleNet
  # Minimal Blizzard REST client, in the same shape as Discord::BotApi. Two
  # authentication modes:
  #
  #   BattleNet::Client.app                        # client credentials — public
  #                                                # game/profile data, no user
  #                                                # involved, token auto-cached
  #   BattleNet::Client.for_user(token, region:)   # one user's OAuth token
  #
  # Blizzard user tokens live 24 hours and third parties get no usable refresh
  # token, so nothing here persists one. The OAuth flow is a *one-time ownership
  # proof* (see BattleNet::LinkAccount): it tells us which characters are really
  # theirs, and every refresh after that runs on the app token against public
  # endpoints. Only discovering newly-created characters needs a re-link.
  #
  # Never call this inside a DB transaction.
  class Client
    Error        = Class.new(StandardError)
    # 401/403 — for a user token this means "expired or revoked, re-link".
    Unauthorized = Class.new(Error)
    NotFound     = Class.new(Error)

    # Regions with their own API host and profile namespace. `cn` is a separate
    # Blizzard deployment with different credentials — deliberately unsupported.
    REGIONS = %w[us eu kr tw].freeze
    DEFAULT_REGION = "us".freeze

    OAUTH_HOST = "https://oauth.battle.net".freeze
    TOKEN_URL  = "#{OAUTH_HOST}/token".freeze

    DEFAULT_LOCALE = "en_US".freeze

    class << self
      # App-authenticated client. Used for everything that doesn't need a
      # specific person's consent, which after linking is everything.
      def app(region: DEFAULT_REGION)
        new(token: app_token, region: region)
      end

      # User-authenticated client, for the ~24h a link ceremony's token is live.
      def for_user(token, region: DEFAULT_REGION)
        new(token: token, region: region)
      end

      def configured? = client_id.present? && client_secret.present?

      def client_id     = ENV["BLIZZARD_CLIENT_ID"].to_s.strip
      def client_secret = ENV["BLIZZARD_CLIENT_SECRET"].to_s.strip

      def region?(region) = REGIONS.include?(region.to_s)

      # Client-credentials token, cached until just before it expires. Shared by
      # every process (Solid Cache is the DB), so the bot, web, and jobs don't
      # each mint their own.
      def app_token
        raise Error, "BLIZZARD_CLIENT_ID/SECRET are not set" unless configured?

        Rails.cache.fetch("battle_net/app_token", expires_in: 1.hour) do
          data = request_app_token
          # Blizzard issues 24h tokens; re-mint hourly anyway so a revoked or
          # rotated secret surfaces fast and the cache never serves a dead token.
          data.fetch("access_token")
        end
      end

      def expire_app_token = Rails.cache.delete("battle_net/app_token")

      private

      def request_app_token
        uri = URI(TOKEN_URL)
        request = Net::HTTP::Post.new(uri)
        request.basic_auth(client_id, client_secret)
        request.set_form_data("grant_type" => "client_credentials")

        response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 5, read_timeout: 5) do |http|
          http.request(request)
        end
        raise Error, "token -> HTTP #{response.code}" unless response.is_a?(Net::HTTPSuccess)

        JSON.parse(response.body)
      end
    end

    attr_reader :region

    def initialize(token:, region: DEFAULT_REGION)
      @token = token
      @region = self.class.region?(region) ? region.to_s : DEFAULT_REGION
    end

    # --- Identity (user token) ---

    # { "sub" => "...", "id" => 12345678, "battletag" => "Name#1234" }
    def userinfo = get_absolute("#{OAUTH_HOST}/userinfo")

    # --- WoW profile (user token) ---

    # The signed-in user's WoW account summary: every character they own, across
    # every WoW account attached to the Battle.net login. This is the payload
    # that makes the whole link worthwhile — it is the only source that proves
    # ownership rather than asserting it.
    def wow_account_profile = get("/profile/user/wow", namespace: :profile)

    # --- WoW profile (app token — public, works forever) ---

    def character_profile(realm_slug, name)
      get("/profile/wow/character/#{realm_slug}/#{slug(name)}", namespace: :profile)
    end

    def character_media(realm_slug, name)
      get("/profile/wow/character/#{realm_slug}/#{slug(name)}/character-media", namespace: :profile)
    end

    def mythic_keystone_profile(realm_slug, name)
      get("/profile/wow/character/#{realm_slug}/#{slug(name)}/mythic-keystone-profile", namespace: :profile)
    end

    def guild_roster(realm_slug, guild_slug)
      get("/data/wow/guild/#{realm_slug}/#{slug(guild_slug)}/roster", namespace: :profile)
    end

    # --- Profession reference data (static namespace) ---

    def profession_index = get("/data/wow/profession/index", namespace: :static)

    def profession(id) = get("/data/wow/profession/#{id}", namespace: :static)

    # Every recipe in one expansion's worth of a profession, grouped into
    # Blizzard's own categories ("Void Potions", "Transmutations", …). The
    # categories exist only here — the per-character payload has none.
    def profession_skill_tier(profession_id, skill_tier_id)
      get("/data/wow/profession/#{profession_id}/skill-tier/#{skill_tier_id}", namespace: :static)
    end

    # Professions with per-expansion skill tiers and known recipes.
    def character_professions(realm_slug, name)
      get("/profile/wow/character/#{realm_slug}/#{slug(name)}/professions", namespace: :profile)
    end

    # Every achievement the character has, earned or not (~3,600 entries for a
    # long-lived character). Heavy — see RefreshCharacterAchievements for why
    # it's worth it and why it runs on its own cadence.
    def character_achievements(realm_slug, name)
      get("/profile/wow/character/#{realm_slug}/#{slug(name)}/achievements", namespace: :profile)
    end

    # Per-boss and per-dungeon kill counts with a `last_updated_timestamp`.
    # Comparing that timestamp against the weekly reset is how wowaudit derives
    # Great Vault progress from public data (see TODOS) — Blizzard exposes no
    # vault endpoint on the app token.
    def character_achievement_statistics(realm_slug, name)
      get("/profile/wow/character/#{realm_slug}/#{slug(name)}/achievements/statistics", namespace: :profile)
    end

    # --- PvP (app token for reference data, public profile for characters) ---

    # Which brackets a character has actually played, plus honor level and
    # lifetime honorable kills. Self-describing: `brackets` lists the exact
    # slugs to query, so nothing has to be guessed or 404-probed.
    def pvp_summary(realm_slug, name)
      get("/profile/wow/character/#{realm_slug}/#{slug(name)}/pvp-summary", namespace: :profile)
    end

    # One bracket's rating, tier and win/loss for the CURRENT season only —
    # Blizzard publishes no historical per-character PvP endpoint.
    # `bracket` is a slug: "2v2", "3v3", "rbg", "shuffle-mage-frost", …
    def pvp_bracket(realm_slug, name, bracket)
      get("/profile/wow/character/#{realm_slug}/#{slug(name)}/pvp-bracket/#{bracket}", namespace: :profile)
    end

    def pvp_season_index = get("/data/wow/pvp-season/index", namespace: :dynamic)

    def pvp_season(id) = get("/data/wow/pvp-season/#{id}", namespace: :dynamic)

    # Title cutoffs, per bracket and specialisation, for one season.
    def pvp_rewards(season_id)
      get("/data/wow/pvp-season/#{season_id}/pvp-reward/index", namespace: :dynamic)
    end

    # Tiers live under the `static` namespace, unlike seasons.
    def pvp_tier_index = get("/data/wow/pvp-tier/index", namespace: :static)

    def pvp_tier(id) = get("/data/wow/pvp-tier/#{id}", namespace: :static)

    # --- Game data (app token) ---

    # { "price" => 2789420000, "last_updated_timestamp" => 1785174057000 }
    # Price is in copper; the timestamp is Blizzard's, not ours. Note the
    # `dynamic` namespace — token data isn't under `profile`.
    def token_index = get("/data/wow/token/index", namespace: :dynamic)

    # --- Primitives ---
    # Public so future integrations can reach an endpoint this class doesn't
    # wrap yet without having to fork it.

    def get(path, namespace: :profile, **params)
      get_absolute("#{api_host}#{path}", namespace: namespace, **params)
    end

    private

    def get_absolute(url, namespace: nil, **params)
      uri = URI(url)
      query = params.compact
      query[:namespace] = "#{namespace}-#{region}" if namespace
      query[:locale] = DEFAULT_LOCALE if namespace
      uri.query = URI.encode_www_form(query) if query.any?

      perform(Net::HTTP::Get.new(uri), uri)
    end

    def perform(request, uri)
      request["Authorization"] = "Bearer #{@token}"
      response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 5, read_timeout: 10) do |http|
        http.request(request)
      end

      case response
      when Net::HTTPSuccess      then response.body.presence && JSON.parse(response.body)
      when Net::HTTPUnauthorized then raise Unauthorized, "#{uri.path} -> HTTP #{response.code}"
      when Net::HTTPForbidden    then raise Unauthorized, "#{uri.path} -> HTTP #{response.code}"
      when Net::HTTPNotFound     then raise NotFound, "#{uri.path} -> HTTP #{response.code}"
      else raise Error, "#{uri.path} -> HTTP #{response.code}"
      end
    end

    def api_host = "https://#{region}.api.blizzard.com"

    # Blizzard wants lowercase, URL-escaped names ("Ünstable" → "%C3%BCnstable").
    def slug(value) = URI.encode_uri_component(value.to_s.downcase)
  end
end
