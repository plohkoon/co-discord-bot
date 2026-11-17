# Enqueued by Teams::Delete: take a deleted team's role off everyone who still
# holds it. Takes the role id rather than the team, which no longer exists.
class TeamRoleStripJob < ApplicationJob
  queue_as :default

  retry_on Discord::BotApi::Error, wait: :polynomially_longer, attempts: 5
  discard_on Discord::BotApi::NotFound # bot kicked or guild gone — nothing to strip

  def perform(guild_id:, role_id:, team_name:)
    guild = Guild.find_by(id: guild_id) or return

    # Two teams can be pointed at the same role. Stripping it would pull the
    # surviving team's whole roster — and RoleSync would then archive them all.
    return if ActsAsTenant.with_tenant(guild) { Team.exists?(team_role_id: role_id) }

    result = Memberships::StripRole.call(guild_id: guild.id, role_id: role_id,
                                         reason: "co-bot: #{team_name} was deleted")
    return unless result.refused

    GuildLog.record(guild: guild, level: :high, title: "Couldn't remove a deleted team's role",
                    description: "**#{team_name}** was deleted, but Discord refused to remove <@&#{role_id}> " \
                                 "from its members (#{result.removed} removed before that). " \
                                 "Give the bot Manage Roles with its highest role above that role, " \
                                 "then remove it by hand or delete the role.",
                    color: 0xED4245)
  end
end
