require "net/http"

module Discord
  # Fetch the signed-in user's guilds via the OAuth token and partition the ones
  # they hold Manage Server on: `manageable` (co-bot is or was installed — we
  # have a Guild row) and `installable` (no row yet — the dashboard offers an
  # "Add co-bot" card). Entries are compact {"id","name","icon"} hashes.
  # `member` is the ids of every known guild the user simply belongs to
  # (Manage Server or not) — membership grants view access on the web.
  class ManageableGuilds
    MANAGE_GUILD = 1 << 5
    ENDPOINT = "https://discord.com/api/v10/users/@me/guilds"

    Result = Struct.new(:manageable, :installable, :member)

    def self.call(token:) = new(token:).call

    def initialize(token:)
      @token = token
    end

    def call
      known = Guild.pluck(:id).to_set
      all = fetch
      managed = all.select { |g| manager?(g) }
      matched, installable = managed.partition { |g| known.include?(g["id"].to_i) }
      member = all.select { |g| known.include?(g["id"].to_i) }.map { |g| g["id"].to_s }
      Rails.logger.info("[web] manageable guilds: managed=#{managed.size} known=#{known.size} matched=#{matched.size} installable=#{installable.size} member=#{member.size}")
      Result.new(compact(matched), compact(installable), member)
    rescue => e
      Rails.logger.error("[web] fetching Discord guilds failed: #{e.class}: #{e.message}")
      Result.new([], [], [])
    end

    private

    def compact(guilds)
      guilds.map { |g| { "id" => g["id"].to_s, "name" => g["name"], "icon" => g["icon"] } }
    end

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
