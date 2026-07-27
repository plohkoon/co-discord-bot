require "net/http"

module WarcraftLogs
  # Warcraft Logs v2 client. Same shape as BattleNet::Client and
  # RaiderIo::Client, with two differences that come from the API itself:
  #
  # 1. It is **GraphQL**, one POST endpoint, queries as strings. No gem — the
  #    handful of queries here are static documents with variables.
  # 2. It is rate-limited by **points, not requests**: 3,600/hour on client
  #    credentials, and a query's cost scales with how much data it asks for.
  #    `rate_limit` reports the running total; a query that overruns answers
  #    with an error rather than truncating.
  #
  # Auth is OAuth2 client credentials only — no user consent involved, so this
  # works for any character without the person being present. Tokens are cached
  # like Blizzard's.
  #
  # Never call this inside a DB transaction.
  class Client
    Error = Class.new(StandardError)
    # Token rejected/expired, or credentials wrong.
    Unauthorized = Class.new(Error)
    # The character/guild isn't on Warcraft Logs. Extremely common and not an
    # error: it just means they've never been in a logged raid.
    NotFound = Class.new(Error)
    # Points exhausted for the hour.
    RateLimited = Class.new(Error)

    ENDPOINT  = "https://www.warcraftlogs.com/api/v2/client".freeze
    TOKEN_URL = "https://www.warcraftlogs.com/oauth/token".freeze

    class << self
      def configured? = client_id.present? && client_secret.present?

      def client_id     = ENV["WARCRAFTLOGS_CLIENT_ID"].to_s.strip
      def client_secret = ENV["WARCRAFTLOGS_CLIENT_SECRET"].to_s.strip

      # Cached in Solid Cache so the bot, web and job processes share one token.
      # Warcraft Logs issues long-lived tokens; re-minting hourly keeps a
      # rotated secret from going unnoticed.
      def access_token
        raise Error, "WARCRAFTLOGS_CLIENT_ID/SECRET are not set" unless configured?

        Rails.cache.fetch("warcraft_logs/access_token", expires_in: 1.hour) do
          request_token.fetch("access_token")
        end
      end

      def expire_access_token = Rails.cache.delete("warcraft_logs/access_token")

      private

      def request_token
        uri = URI(TOKEN_URL)
        request = Net::HTTP::Post.new(uri)
        request.basic_auth(client_id, client_secret)
        request.set_form_data("grant_type" => "client_credentials")

        response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 5, read_timeout: 10) do |http|
          http.request(request)
        end
        raise Unauthorized, "token -> HTTP #{response.code}" if response.is_a?(Net::HTTPUnauthorized)
        raise Error, "token -> HTTP #{response.code}" unless response.is_a?(Net::HTTPSuccess)

        JSON.parse(response.body)
      end
    end

    # --- Queries ---
    # Kept as constants rather than built at call time: they're static
    # documents, and a typo should be visible in one place.

    RATE_LIMIT = <<~GQL.freeze
      query { rateLimitData { limitPerHour pointsSpentThisHour pointsResetIn } }
    GQL

    # `frozen` is the field that matters most here: a frozen zone is a closed
    # tier whose rankings can never change again (see WarcraftLogsZone).
    ZONES = <<~GQL.freeze
      query($expansionID: Int) {
        worldData {
          zones(expansion_id: $expansionID) {
            id
            name
            frozen
            expansion { id name }
            difficulties { id name }
            # journalID is Blizzard's journal encounter id — the same number
            # Raider.io returns as its encounter id, and therefore the only
            # reliable way to line the two services' tiers up (see WowEncounter).
            encounters { id name journalID }
          }
        }
      }
    GQL

    # zoneRankings is a JSON **scalar** — it takes arguments but has no
    # sub-selection, and comes back as an opaque object we parse ourselves.
    CHARACTER_ZONE_RANKINGS = <<~GQL.freeze
      query($name: String!, $serverSlug: String!, $serverRegion: String!,
            $zoneID: Int, $difficulty: Int, $metric: CharacterPageRankingMetricType) {
        characterData {
          character(name: $name, serverSlug: $serverSlug, serverRegion: $serverRegion) {
            id
            name
            classID
            hidden
            server { slug region { slug } }
            zoneRankings(zoneID: $zoneID, difficulty: $difficulty, metric: $metric)
          }
        }
      }
    GQL

    def initialize(token: nil)
      @token = token
    end

    def rate_limit = query(RATE_LIMIT).dig("rateLimitData")

    def zones(expansion_id: nil)
      query(ZONES, expansionID: expansion_id).dig("worldData", "zones")
    end

    # Returns the character hash (including the parsed zoneRankings object), or
    # raises NotFound when Warcraft Logs has never seen them.
    def character_zone_rankings(name:, server_slug:, region:, zone_id: nil, difficulty: nil, metric: "default")
      data = query(
        CHARACTER_ZONE_RANKINGS,
        name: name, serverSlug: server_slug, serverRegion: region.to_s.upcase,
        zoneID: zone_id, difficulty: difficulty, metric: metric
      )
      data.dig("characterData", "character") or raise NotFound, "character #{name}-#{server_slug}"
    end

    # Public so future queries don't need a fork.
    def query(document, **variables)
      body = { query: document, variables: variables.compact }
      response = post(body)

      case response
      when Net::HTTPSuccess      then unwrap(JSON.parse(response.body))
      when Net::HTTPUnauthorized then raise Unauthorized, "graphql -> 401"
      when Net::HTTPTooManyRequests then raise RateLimited, "graphql -> 429"
      else raise Error, "graphql -> HTTP #{response.code}: #{response.body.to_s[0, 200]}"
      end
    end

    private

    def token = @token ||= self.class.access_token

    def post(body)
      uri = URI(ENDPOINT)
      request = Net::HTTP::Post.new(uri)
      request["Authorization"] = "Bearer #{token}"
      request["Content-Type"] = "application/json"
      request.body = JSON.generate(body)

      Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 5, read_timeout: 15) do |http|
        http.request(request)
      end
    end

    # GraphQL reports failures in a 200 body, so a successful HTTP status says
    # nothing on its own.
    def unwrap(payload)
      errors = Array(payload["errors"])
      if errors.any?
        message = errors.filter_map { |e| e["message"] }.join("; ")
        raise RateLimited, message if message.match?(/rate limit|exceeded.*points/i)
        raise Unauthorized, message if message.match?(/unauthenticated|unauthorized/i)

        raise Error, message.presence || "unknown GraphQL error"
      end

      payload["data"] or raise Error, "GraphQL response had no data"
    end
  end
end
