require "net/http"

module WowAudit
  # wowaudit REST client. Unlike the other three integrations this one is keyed
  # **per raid team** (wowaudit's own unit is a team, and the key is issued by a
  # team admin), so a key is passed in rather than read from ENV.
  #
  # What it adds that the others don't: the team's own roster as its officers
  # maintain it, plus raid signups and attendance. Blizzard says what gear
  # someone has, Raider.io what they've killed, Warcraft Logs how well they
  # played — wowaudit says who is actually on the team and who turned up.
  #
  # wowaudit publishes no machine-readable spec and its 401 body is identical
  # whether a key is wrong, malformed or absent, so the shapes below were
  # established from its own open-source engine (github.com/wowaudit/core) and
  # two independent third-party clients that call the live API. Auth in
  # particular is confirmed twice over: a bare `Authorization: <key>` header,
  # no scheme prefix.
  #
  # Never call this inside a DB transaction.
  class Client
    Error        = Class.new(StandardError)
    Unauthorized = Class.new(Error)
    NotFound     = Class.new(Error)
    RateLimited  = Class.new(Error)

    BASE = "https://wowaudit.com/v1".freeze

    def initialize(api_key:)
      @api_key = api_key.to_s.strip
    end

    def configured? = @api_key.present?

    # The team the key belongs to — the cheapest call, so it doubles as the
    # "is this key any good" check.
    def team = get("/team")

    # The team's roster. Returns a **top-level array** (not an object with a
    # `characters` key) of {id, name, realm, class, role, …}.
    def characters = Array(get("/characters"))

    # The current raid week.
    def period = get("/period")

    # Scheduled raids. `{"raids" => [{id, date, instance, difficulty,
    # present_size, total_size}]}`.
    def raids(include_past: false)
      get("/raids", **(include_past ? { include_past: true } : {}))
    end

    # One raid with its signups and per-encounter selections.
    def raid(id) = get("/raids/#{id}")

    # Public so endpoints this class doesn't wrap yet don't need a fork.
    def get(path, **params)
      raise Unauthorized, "no wowaudit API key" unless configured?

      uri = URI("#{BASE}#{path}")
      uri.query = URI.encode_www_form(params.compact) if params.compact.any?

      request = Net::HTTP::Get.new(uri)
      # A bare key, no "Bearer" prefix — confirmed against two live clients.
      request["Authorization"] = @api_key
      request["Accept"] = "application/json"

      response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 5, read_timeout: 15) do |http|
        http.request(request)
      end

      case response
      when Net::HTTPSuccess         then parse(response)
      when Net::HTTPUnauthorized    then raise Unauthorized, "#{path} -> 401"
      when Net::HTTPForbidden       then raise Unauthorized, "#{path} -> 403"
      when Net::HTTPNotFound        then raise NotFound, "#{path} -> 404"
      when Net::HTTPTooManyRequests then raise RateLimited, "#{path} -> 429"
      else raise Error, "#{path} -> HTTP #{response.code}"
      end
    end

    private

    def parse(response)
      body = response.body.to_s
      return nil if body.blank?

      JSON.parse(body)
    rescue JSON::ParserError
      raise Error, "wowaudit returned a non-JSON body: #{body[0, 120]}"
    end
  end
end
