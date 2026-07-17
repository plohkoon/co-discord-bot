module Memberships
  # Hierarchy-safe granting/revoking of a team role. Shared by the accept/reject
  # buttons and the /team member commands.
  module RoleManager
    module_function

    def grant(bot:, server:, team:, discord_user_id:)
      role = server.role(team.team_role_id) or raise RoleError, "the team role no longer exists"
      ensure_manageable!(bot, server, role)
      member = server.member(discord_user_id) or raise RoleError, "the member has left the server"
      member.add_role(role, "co-bot: added to #{team.name}")
    end

    def revoke(bot:, server:, team:, discord_user_id:)
      role = server.role(team.team_role_id) or raise RoleError, "the team role no longer exists"
      ensure_manageable!(bot, server, role)
      member = server.member(discord_user_id)
      return unless member # already gone

      member.remove_role(role, "co-bot: removed from #{team.name}")
    end

    def ensure_manageable!(bot, server, role)
      me = server.member(bot.profile.id) or raise RoleError, "I couldn't find my own membership in this server"
      unless me.permission?(:manage_roles) || me.permission?(:administrator)
        raise RoleError, "I need the **Manage Roles** permission"
      end
      if me.highest_role.position <= role.position
        raise RoleError, "my highest role must be above **#{role.name}** (Server Settings → Roles)"
      end
    end
  end
end
