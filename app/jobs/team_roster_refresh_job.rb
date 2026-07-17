# Repaint the roster message containing a team after the team changed (slash
# command or web edit). Teams can share one Components-V2 message, so the whole
# message is rebuilt from every team posted in it. REST-only: leads come from
# one member-pagination pass. No-op if no roster was posted.
class TeamRosterRefreshJob < ApplicationJob
  queue_as :default

  retry_on Discord::BotApi::Error, wait: :polynomially_longer, attempts: 3

  def perform(guild_id:, team_id:)
    guild = Guild.find_by(id: guild_id) or return

    ActsAsTenant.with_tenant(guild) do
      team = Team.find_by(id: team_id) or next
      next unless team.roster_channel_id && team.roster_message_id

      teams = Team.where(roster_channel_id: team.roster_channel_id,
                         roster_message_id: team.roster_message_id)
                  .includes(:team_category).to_a

      api = Discord::BotApi.new
      begin
        api.edit_message(team.roster_channel_id, team.roster_message_id,
                         CoBot::RosterMessage.refresh_payload(teams, lead_ids_by_team(api, guild_id, teams)))
      rescue Discord::BotApi::NotFound
        # The roster post was deleted (or the bot lost the channel) — forget it
        # so future edits stop trying.
        Team.where(id: teams.map(&:id)).update_all(roster_channel_id: nil, roster_message_id: nil)
      end
    end
  end

  private

  # One pass over the member list, bucketing lead ids by each team's officer role.
  def lead_ids_by_team(api, guild_id, teams)
    by_role = teams.to_h { |team| [ team.officer_role_id.to_s, [] ] }
    api.each_guild_member(guild_id) do |member|
      next if member.dig("user", "bot")

      Array(member["roles"]).map(&:to_s).each do |role_id|
        by_role[role_id] << member.dig("user", "id") if by_role.key?(role_id)
      end
    end
    teams.to_h { |team| [ team.id, by_role.fetch(team.officer_role_id.to_s, []) ] }
  end
end
