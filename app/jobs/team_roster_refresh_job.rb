# Repaint the roster message containing a team after the team changed (slash
# command or web edit). Teams can share one Components-V2 message, so the whole
# message is rebuilt from every team posted in it. Cheap: leads come from the
# local team_officers mirror, so it's one REST edit and zero member paging.
# No-op if no roster was posted.
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
                  .includes(:team_category, :team_officers).to_a

      api = Discord::BotApi.new
      begin
        api.edit_message(team.roster_channel_id, team.roster_message_id,
                         CoBot::RosterMessage.refresh_payload(teams, CoBot::RosterMessage.role_colors(api, teams)))
      rescue Discord::BotApi::NotFound
        # The roster post was deleted (or the bot lost the channel) — forget it
        # so future edits stop trying.
        Team.where(id: teams.map(&:id)).update_all(roster_channel_id: nil, roster_message_id: nil)
      end
    end
  end
end
