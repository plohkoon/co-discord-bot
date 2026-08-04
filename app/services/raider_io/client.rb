require "net/http"

module RaiderIo
  # Raider.io REST client, same shape as BattleNet::Client and Discord::BotApi.
  #
  # No authentication: every endpoint used here is public. An API key only
  # raises the rate limit, so the integration degrades to "slower", never
  # "broken", when RAIDER_IO_API_KEY is unset.
  #
  # Rate limit is 200 requests/minute unauthenticated — considerably tighter
  # than Blizzard's 36,000/hour, so Raider.io is the binding constraint on any
  # bulk refresh. Keep it best-effort and let the sweep spread the work.
  #
  # Never call this inside a DB transaction.
  class Client
    Error = Class.new(StandardError)
    # Raider.io answers an unknown character with **HTTP 400**, not 404:
    #   {"statusCode":400,"error":"Bad Request",
    #    "message":"Could not find requested character"}
    # so a naive "400 means we sent something malformed" reading is wrong here.
    NotFound = Class.new(Error)
    # Also a 400: "Requested unsupported expansion_id". Its own class because
    # probing expansion ids upward is how SyncStaticData discovers the newest
    # one — hitting the ceiling is the expected end of the loop, not a fault.
    Unsupported = Class.new(Error)
    # 429 — back off, don't retry tightly.
    RateLimited = Class.new(Error)

    BASE = "https://raider.io/api/v1".freeze

    # Everything a recruiting-minded lead wants and Blizzard won't give plainly.
    CHARACTER_FIELDS = %w[
      mythic_plus_scores_by_season:current
      raid_progression
      gear
    ].freeze

    def self.character_profile(...) = new.character_profile(...)

    def initialize(api_key: ENV["RAIDER_IO_API_KEY"].to_s.strip.presence)
      @api_key = api_key
    end

    # nil when Raider.io has never crawled this character.
    def character_profile(region:, realm:, name:, fields: CHARACTER_FIELDS)
      get("/characters/profile", region: region, realm: realm, name: name, fields: Array(fields).join(","))
    end

    def guild_profile(region:, realm:, name:, fields: %w[raid_progression])
      get("/guilds/profile", region: region, realm: realm, name: name, fields: Array(fields).join(","))
    end

    # Mythic+ score percentiles for a region: top 0.1%/1%/10%, the named title
    # tiers, population counts and faction splits. Blizzard publishes no
    # equivalent, so this is the only source of "what was that score worth".
    #
    # `season` is documented as optional but omitting it returns a 500, not a
    # default — always pass it.
    def mythic_plus_season_cutoffs(region:, season:)
      get("/mythic-plus/season-cutoffs", region: region, season: season)
    end

    # Which Mythic+ seasons exist for an expansion, with their start/end times.
    def mythic_plus_static_data(expansion_id:)
      get("/mythic-plus/static-data", expansion_id: expansion_id)
    end

    # Which raid tiers exist for an expansion, with names and encounter lists.
    def raiding_static_data(expansion_id:)
      get("/raiding/static-data", expansion_id: expansion_id)
    end

    # Season scores are selected by colon-appending slugs to the field name, and
    # several can ride in one request:
    #   mythic_plus_scores_by_season:current:season-tww-3:season-tww-2
    # which is what makes backfilling a character's whole history one call.
    # `current` and `previous` are accepted alongside real slugs.
    def self.season_field(*selectors)
      "mythic_plus_scores_by_season:#{Array(selectors).flatten.join(":")}"
    end

    # Public so future endpoints don't need a fork.
    def get(path, **params)
      params[:access_key] = @api_key if @api_key
      uri = URI("#{BASE}#{path}")
      uri.query = URI.encode_www_form(params.compact)

      response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 5, read_timeout: 10) do |http|
        http.request(Net::HTTP::Get.new(uri))
      end

      case response
      when Net::HTTPSuccess         then JSON.parse(response.body)
      when Net::HTTPTooManyRequests then raise RateLimited, "#{path} -> 429"
      when Net::HTTPNotFound        then raise NotFound, "#{path} -> 404"
      when Net::HTTPBadRequest      then raise bad_request_error(path, response)
      else raise Error, "#{path} -> HTTP #{response.code}"
      end
    end

    private

    # Raider.io overloads 400 for several unrelated outcomes, so the message is
    # the only way to tell an expected "we don't have that" from a request we
    # actually built wrong.
    def bad_request_error(path, response)
      message = begin
        JSON.parse(response.body.to_s)["message"].to_s
      rescue JSON::ParserError
        ""
      end

      return NotFound.new("#{path} -> #{message}") if message.match?(/could not find/i)
      return Unsupported.new("#{path} -> #{message}") if message.match?(/unsupported/i)

      Error.new("#{path} -> 400 #{message}")
    end
  end
end
