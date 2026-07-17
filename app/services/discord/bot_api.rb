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
    # 403 specifically — a subclass of NotFound so existing "bot was kicked"
    # handling still catches it, while callers that need to can tell a
    # permission refusal apart from a genuinely missing resource.
    Forbidden = Class.new(NotFound)

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

    def guild_channels(guild_id) = get("/guilds/#{guild_id}/channels")

    def guild_emojis(guild_id) = get("/guilds/#{guild_id}/emojis")

    def guild_member(guild_id, user_id) = get("/guilds/#{guild_id}/members/#{user_id}")

    # Page through the guild's full member list — the REST equivalent of
    # gateway member chunking, usable from web/job processes. Yields each raw
    # member hash ({"user" => {...}, "roles" => [...], ...}).
    MEMBERS_PAGE_SIZE = 1000

    def each_guild_member(guild_id)
      after = 0
      loop do
        page = get("/guilds/#{guild_id}/members?limit=#{MEMBERS_PAGE_SIZE}&after=#{after}")
        page.each { |member| yield member }
        break if page.size < MEMBERS_PAGE_SIZE

        after = page.map { |m| m.dig("user", "id").to_i }.max
      end
    end

    # Follow-up message to an already-acked interaction. Authenticated by the
    # token in the path (valid ~15 minutes after the ack), so any process can
    # send it — no gateway connection involved.
    def interaction_followup(application_id:, token:, content:, ephemeral: true)
      post("/webhooks/#{application_id}/#{token}", "content" => content, "flags" => ephemeral ? 64 : 0)
    end

    # Grant/pull a role (204 on success). Discord enforces Manage Roles and the
    # role hierarchy server-side — refusals surface as Forbidden.
    def add_member_role(guild_id, user_id, role_id, reason: nil)
      put("/guilds/#{guild_id}/members/#{user_id}/roles/#{role_id}", reason: reason)
    end

    def remove_member_role(guild_id, user_id, role_id, reason: nil)
      delete("/guilds/#{guild_id}/members/#{user_id}/roles/#{role_id}", reason: reason)
    end

    def create_message(channel_id, payload) = post("/channels/#{channel_id}/messages", payload)

    def edit_message(channel_id, message_id, payload) = patch("/channels/#{channel_id}/messages/#{message_id}", payload)

    def delete_message(channel_id, message_id) = delete("/channels/#{channel_id}/messages/#{message_id}")

    private

    def get(path)
      perform(Net::HTTP::Get.new(URI("#{BASE}#{path}")), path)
    end

    def post(path, body)
      write(Net::HTTP::Post, path, body)
    end

    def patch(path, body)
      write(Net::HTTP::Patch, path, body)
    end

    def put(path, reason: nil)
      request = Net::HTTP::Put.new(URI("#{BASE}#{path}"))
      request["X-Audit-Log-Reason"] = URI.encode_uri_component(reason) if reason
      request["Content-Length"] = "0"
      perform(request, path)
    end

    def delete(path, reason: nil)
      request = Net::HTTP::Delete.new(URI("#{BASE}#{path}"))
      request["X-Audit-Log-Reason"] = URI.encode_uri_component(reason) if reason
      perform(request, path)
    end

    def write(verb, path, body)
      request = verb.new(URI("#{BASE}#{path}"))
      request["Content-Type"] = "application/json"
      request.body = JSON.generate(body)
      perform(request, path)
    end

    def perform(request, path)
      request["Authorization"] = "Bot #{@token}"
      uri = request.uri
      response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 5, read_timeout: 5) do |http|
        http.request(request)
      end

      case response
      when Net::HTTPSuccess   then response.body.presence && JSON.parse(response.body)
      when Net::HTTPForbidden then raise Forbidden, "#{path} -> HTTP #{response.code}"
      when Net::HTTPNotFound  then raise NotFound, "#{path} -> HTTP #{response.code}"
      else raise Error, "#{path} -> HTTP #{response.code}"
      end
    end
  end
end
