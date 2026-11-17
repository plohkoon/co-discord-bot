module Teams
  # Deletes a team for good: the row and everything hanging off it (members,
  # applications and their answers, notes, questions, the officers mirror,
  # call-outs, wowaudit roster) go in one transaction, then the team role is
  # pulled from everyone who holds it in the background.
  #
  # The rows go FIRST, deliberately. Pulling roles while the team still exists
  # would make every role removal a member_update that RoleSync turns into an
  # archive — rejecting pending applications and logging a removal per member,
  # all for a team about to vanish. With the team gone, those updates match
  # nothing. The job carries the role id itself, so it needs no row to work.
  #
  # The Discord role itself is left alone: it may carry channel permissions or
  # history the server wants to keep, and deleting it is one click in Discord.
  # Caller must set the tenant.
  module Delete
    module_function

    def call(team:, actor_id: nil)
      guild = team.guild
      name = team.name
      role_id = team.team_role_id

      team.destroy!

      TeamRoleStripJob.perform_later(guild_id: guild.id, role_id: role_id, team_name: name)
      # Drops the team's block from any posted roster; a no-op if none is.
      RosterRefreshJob.perform_later(guild_id: guild.id)
      GuildLog.record(guild: guild, level: :high, title: "Team deleted",
                      description: "**#{name}** was deleted. Its role <@&#{role_id}> is being removed from everyone who has it.",
                      actor_id: actor_id, color: 0xED4245)
    end
  end
end
