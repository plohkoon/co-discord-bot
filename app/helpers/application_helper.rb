module ApplicationHelper
  # Permissions requested when inviting the bot: Manage Roles (it grants/revokes
  # team roles). Changing this after launch means servers must re-invite.
  BOT_INVITE_PERMISSIONS = 1 << 28

  # Discord's "Add to Server" URL. With a guild_id the server is pre-selected
  # and locked, so the Discord side is a single click.
  def discord_install_url(guild_id: nil)
    params = {
      client_id: ENV["DISCORD_CLIENT_ID"],
      scope: "bot applications.commands",
      permissions: BOT_INVITE_PERMISSIONS
    }
    params.merge!(guild_id: guild_id, disable_guild_select: true) if guild_id
    "https://discord.com/oauth2/authorize?#{params.to_query}"
  end
end
