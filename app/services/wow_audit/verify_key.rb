module WowAudit
  # Check a team's wowaudit key and record the result.
  #
  # wowaudit offers no way to tell a good key from a bad one except by using it,
  # so this makes the cheapest real call (/v1/team) and stores the answer. Run
  # on save: silently keeping an unchecked credential just moves the failure
  # somewhere less visible.
  class VerifyKey
    Result = Struct.new(:ok, :team_name, :error, keyword_init: true) do
      def ok? = !!ok
    end

    def self.call(...) = new(...).call

    def initialize(team, client: nil)
      @team = team
      @client = client || Client.new(api_key: team.wowaudit_api_key)
    end

    def call
      return failure("No wowaudit API key set.") unless @client.configured?

      payload = @client.team
      name = payload.is_a?(Hash) ? (payload["name"] || payload.dig("team", "name")) : nil
      @team.update!(wowaudit_verified_at: Time.current, wowaudit_team_name: name)
      Result.new(ok: true, team_name: name)
    rescue Client::Unauthorized
      failure("wowaudit rejected the key.")
    rescue Client::Error => e
      failure("wowaudit request failed: #{e.message}")
    end

    private

    def failure(message)
      @team.update!(wowaudit_verified_at: nil)
      Result.new(ok: false, error: message)
    end
  end
end
