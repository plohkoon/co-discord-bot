require "net/http"

module Discord
  # The signed-in user's linked third-party accounts, read once at login with
  # their OAuth token (needs the `connections` scope).
  #
  # Discord already knows whether someone has attached a Battle.net account, and
  # it verified that link itself — so this is a free head start on the WoW
  # integration: we learn a user's BattleTag without asking Blizzard anything.
  # It is a *hint*, not proof of character ownership; only BattleNet::LinkAccount
  # can establish that. Where both exist we cross-check them (see
  # BattleNetAccount#matches_discord_connection?).
  #
  # Deliberately generic: Discord exposes ~34 connection types, so adding Steam
  # or Xbox later is a lookup, not a new service.
  class Connections
    ENDPOINT = "https://discord.com/api/v10/users/@me/connections".freeze

    BATTLE_NET = "battlenet".freeze

    Connection = Struct.new(:type, :id, :name, :verified, keyword_init: true) do
      def verified? = !!verified
    end

    def self.call(token:) = new(token: token).call

    def initialize(token:)
      @token = token
    end

    # Always returns an array — a failure here must never block a login.
    def call
      fetch.filter_map do |raw|
        next unless raw.is_a?(Hash) && raw["type"].present?

        Connection.new(
          type: raw["type"].to_s,
          id: raw["id"].to_s,
          name: raw["name"].to_s,
          verified: raw["verified"]
        )
      end
    end

    # Convenience for the common case: the user's verified Battle.net link, or nil.
    def self.battle_net(token:)
      call(token: token).find { |c| c.type == BATTLE_NET && c.verified? }
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

      # 401 here almost always means the user authorized before we asked for the
      # `connections` scope — harmless, they'll re-consent on next sign-in.
      Rails.logger.info("[web] /users/@me/connections -> HTTP #{response.code}")
      []
    rescue => e
      Rails.logger.warn("[web] fetching Discord connections failed: #{e.class}: #{e.message}")
      []
    end
  end
end
