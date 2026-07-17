# Repaint one team's block in the posted /team roster directory after the team
# changed (slash command or web edit). REST-only: leads come from member
# pagination, the message is edited in place. No-op if no roster was posted.
class TeamRosterRefreshJob < ApplicationJob
  queue_as :default

  retry_on Discord::BotApi::Error, wait: :polynomially_longer, attempts: 3

  def perform(guild_id:, team_id:)
    guild = Guild.find_by(id: guild_id) or return

    ActsAsTenant.with_tenant(guild) do
      team = Team.find_by(id: team_id) or next
      next unless team.roster_channel_id && team.roster_message_id

      api = Discord::BotApi.new
      begin
        api.edit_message(team.roster_channel_id, team.roster_message_id,
                         "content" => CoBot::RosterMessage.team_block(team, lead_ids(api, team)),
                         "components" => CoBot::RosterMessage.apply_view(team).to_a,
                         "allowed_mentions" => { "parse" => [] })
      rescue Discord::BotApi::NotFound
        # The roster post was deleted (or the bot lost the channel) — forget it
        # so future edits stop trying.
        team.update(roster_channel_id: nil, roster_message_id: nil)
      end
    end
  end

  private

  def lead_ids(api, team)
    role_id = team.officer_role_id.to_s
    ids = []
    api.each_guild_member(team.guild_id) do |member|
      next unless Array(member["roles"]).map(&:to_s).include?(role_id)
      next if member.dig("user", "bot")

      ids << member.dig("user", "id")
    end
    ids
  end
end
