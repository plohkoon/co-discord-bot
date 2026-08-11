module Memberships
  # REST counterpart of RoleManager for processes without a gateway connection
  # (web, jobs). Discord enforces Manage Roles + the role hierarchy server-side,
  # so there's no pre-flight check here — refusals come back as RoleError with
  # the same actionable messages RoleManager raises.
  module RestRoleManager
    module_function

    def grant(team:, discord_user_id:, api: Discord::BotApi.new)
      api.add_member_role(team.guild_id, discord_user_id, team.team_role_id,
                          reason: "co-bot: added to #{team.name}")
    rescue Discord::BotApi::Forbidden
      raise RoleError, refusal_message
    rescue Discord::BotApi::NotFound
      # Discord's 404 doesn't say WHICH resource was unknown (member vs role),
      # and the two cases must diverge: an absent member is expected for web
      # applicants who haven't joined yet (MemberNotInGuild — accept proceeds,
      # role deferred to the join reconcile), while a vanished role is a real
      # configuration problem. One extra request, on the failure path only.
      raise MemberNotInGuild, "the member isn't in the server" unless member_in_guild?(api, team.guild_id, discord_user_id)

      raise RoleError, "the team role no longer exists"
    rescue Discord::BotApi::Error => e
      raise RoleError, "Discord API error (#{e.message})"
    end

    def revoke(team:, discord_user_id:, api: Discord::BotApi.new)
      api.remove_member_role(team.guild_id, discord_user_id, team.team_role_id,
                             reason: "co-bot: removed from #{team.name}")
    rescue Discord::BotApi::Forbidden
      raise RoleError, refusal_message
    rescue Discord::BotApi::NotFound
      # Member already left or the role is gone — nothing to revoke.
    rescue Discord::BotApi::Error => e
      raise RoleError, "Discord API error (#{e.message})"
    end

    def refusal_message
      "the bot needs the Manage Roles permission with its highest role above the team role (Server Settings → Roles)"
    end

    def member_in_guild?(api, guild_id, discord_user_id)
      api.guild_member(guild_id, discord_user_id)
      true
    rescue Discord::BotApi::Forbidden
      # The bot can't see the guild — that says nothing about the member, and
      # is a real refusal, not the expected "hasn't joined yet" case.
      raise RoleError, refusal_message
    rescue Discord::BotApi::NotFound
      false
    end
  end
end
