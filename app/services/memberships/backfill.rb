module Memberships
  # One pass over the guild's members at team creation: everyone holding the
  # team role becomes an active member (same Activate path as the member_update
  # listener, so they get the synthetic accepted manual application), and the
  # team_officers mirror is seeded from the officer role (and pruned, so
  # re-runs self-correct). Idempotent. Returns the member count.
  #
  # REST-based (Discord::BotApi member pagination), so it runs anywhere —
  # normally inside TeamBackfillJob on a Solid Queue worker, no gateway needed.
  # This is the only place that pages the member list; everything else reads
  # the mirrors maintained by RoleSync. Caller must set the tenant.
  module Backfill
    module_function

    def call(team:, api: Discord::BotApi.new)
      team_role = team.team_role_id.to_s
      officer_role = team.officer_role_id.to_s
      count = 0
      officer_ids = []

      api.each_guild_member(team.guild_id) do |member|
        user = member["user"] || {}
        next if user["bot"]

        roles = Array(member["roles"]).map(&:to_s)
        if roles.include?(team_role)
          Activate.call(team: team, discord_user_id: user["id"], username: user["username"])
          count += 1
        end
        if roles.include?(officer_role)
          RoleSync.sync_officer(team, user["id"], user["username"], officer: true)
          officer_ids << user["id"].to_s
        end
      end

      team.team_officers.where.not(discord_user_id: officer_ids).delete_all
      count
    end
  end
end
