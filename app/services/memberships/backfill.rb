module Memberships
  # Sweep everyone already holding the team role into the team as active
  # members — the same Activate path as the member_update listener, so they get
  # the synthetic accepted application with source: manual. Idempotent.
  #
  # REST-based (Discord::BotApi member pagination), so it runs anywhere —
  # normally inside TeamBackfillJob on a Solid Queue worker, no gateway needed.
  # Caller must set the tenant.
  module Backfill
    module_function

    def call(team:, api: Discord::BotApi.new)
      role_id = team.team_role_id.to_s
      count = 0
      api.each_guild_member(team.guild_id) do |member|
        next unless Array(member["roles"]).map(&:to_s).include?(role_id)

        user = member["user"] || {}
        next if user["bot"]

        Activate.call(team: team, discord_user_id: user["id"], username: user["username"])
        count += 1
      end
      count
    end
  end
end
