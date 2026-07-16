require "net/http"

module Discord
  # Fetch the signed-in user's guilds via the OAuth token, and keep only the ones
  # where (a) co-bot is installed and (b) the user has Manage Server. Returns a
  # compact array of hashes suitable for stashing in the session.
  class ManageableGuilds
    MANAGE_GUILD = 1 << 5
    ENDPOINT = "https://discord.com/api/v10/users/@me/guilds"

    def self.call(token:) = new(token:).call

    def initialize(token:)
      @token = token
    end

    def call
      installed = Guild.pluck(:id).to_set
      guilds = fetch
      matched = guilds.select { |g| installed.include?(g["id"].to_i) && manager?(g) }
      Rails.logger.info("[web] manageable guilds: fetched=#{guilds.size} installed=#{installed.size} matched=#{matched.size}")
      matched.map { |g| { "id" => g["id"].to_s, "name" => g["name"], "icon" => g["icon"] } }
    rescue => e
      Rails.logger.error("[web] fetching Discord guilds failed: #{e.class}: #{e.message}")
      []
    end

    private

    def fetch
      uri = URI(ENDPOINT)
      request = Net::HTTP::Get.new(uri)
      request["Authorization"] = "Bearer #{@token}"
      response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 5, read_timeout: 5) do |http|
        http.request(request)
      end

      return JSON.parse(response.body) if response.is_a?(Net::HTTPSuccess)

      Rails.logger.warn("[web] /users/@me/guilds -> HTTP #{response.code}: #{response.body.to_s[0, 300]}")
      []
    end

    def manager?(guild)
      guild["owner"] || (guild["permissions"].to_i & MANAGE_GUILD) == MANAGE_GUILD
    end
  end
end
