module ApplicationHelper
  # Permissions requested when inviting the bot. Changing this after launch
  # means existing servers must re-authorize (visiting the install URL again
  # updates the bot's role in place). Mirror changes in Discord::GuildHealth.
  BOT_INVITE_PERMISSIONS =
    (1 << 28) | # Manage Roles — grant/revoke team roles
    (1 << 10) | # View Channels
    (1 << 11) | # Send Messages — review messages, roster, reminders
    (1 << 14) | # Embed Links — review message embeds
    (1 << 16) | # Read Message History — reminder replies reference the review message
    (1 << 6)    # Add Reactions — message actions

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

  # Custom Discord emotes are stored in mention form (<:name:id> / <a:name:id>),
  # which only renders inside Discord — on the web, show the image straight off
  # Discord's CDN. Unicode emotes (or anything else) render as plain text.
  CUSTOM_EMOTE = /\A<(?<animated>a?):\w+:(?<id>\d+)>\z/

  def discord_emote_tag(emote)
    return if emote.blank?

    match = emote.match(CUSTOM_EMOTE)
    return emote unless match

    image_tag("https://cdn.discordapp.com/emojis/#{match[:id]}.#{match[:animated] == 'a' ? 'gif' : 'png'}",
              alt: "", class: "inline-block w-5 h-5")
  end
end
