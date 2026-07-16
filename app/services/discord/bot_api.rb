require "net/http"

module Discord
  # Minimal Discord REST client authenticated as the bot. Used by web-side
  # services (no gateway connection needed) — the bot and web app still share
  # nothing in-process. Never call this inside a DB transaction.
  class BotApi
    Error    = Class.new(StandardError)
    # Raised when Discord says the bot can't see the guild (404 Unknown Guild,
    # or 403 Missing Access after being kicked).
    NotFound = Class.new(Error)

    BASE = "https://discord.com/api/v10"

    def initialize(token: ENV["DISCORD_BOT_TOKEN"].to_s)
      @token = token
    end

    def configured? = @token.strip.present?

    # The bot's own user id — stable for the lifetime of the token.
    def bot_user_id
      Rails.cache.fetch("discord/bot_user_id", expires_in: 1.day) { get("/users/@me")["id"] }
    end

    def guild_roles(guild_id) = get("/guilds/#{guild_id}/roles")

    def guild_member(guild_id, user_id) = get("/guilds/#{guild_id}/members/#{user_id}")

    private

    def get(path)
      uri = URI("#{BASE}#{path}")
      request = Net::HTTP::Get.new(uri)
      request["Authorization"] = "Bot #{@token}"
      response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 5, read_timeout: 5) do |http|
        http.request(request)
      end

      case response
      when Net::HTTPSuccess               then JSON.parse(response.body)
      when Net::HTTPNotFound, Net::HTTPForbidden then raise NotFound, "#{path} -> HTTP #{response.code}"
      else raise Error, "#{path} -> HTTP #{response.code}"
      end
    end
  end
end
