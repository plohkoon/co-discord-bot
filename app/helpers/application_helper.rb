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
  # (Loading from the CDN is deliberate: it's public, unauthenticated and
  # edge-cached, so there's nothing to gain by proxying or caching copies.)
  # Name charset mirrors Discord::EmoteResolver's.
  CUSTOM_EMOTE = /\A<(?<animated>a?):(?<name>[a-zA-Z0-9_~]+):(?<id>\d+)>\z/

  # Split-with-capture form of CUSTOM_EMOTE: String#split keeps the captured
  # mentions interleaved with the surrounding text.
  INLINE_EMOTE = /(<a?:[a-zA-Z0-9_~]+:\d+>)/

  def discord_emote_tag(emote)
    return if emote.blank?

    match = emote.match(CUSTOM_EMOTE)
    return emote unless match

    discord_emote_image(match, css_class: "inline-block w-5 h-5")
  end

  # Free-typed text fields (team bios, roster lines, guild descriptions) carry
  # emote mentions inline — EmoteResolver.resolve_text normalizes :name: to
  # mention form at save. Render the text with each mention swapped for its
  # CDN image, sized to ride along with the surrounding text. Everything else
  # is user input and gets escaped (safe_join escapes the plain segments).
  def discord_emotes(text)
    return text if text.blank?

    safe_join(text.to_s.split(INLINE_EMOTE).map do |part|
      match = part.match(CUSTOM_EMOTE)
      match ? discord_emote_image(match, css_class: "inline-block h-[1.25em] w-[1.25em] align-middle") : part
    end)
  end

  private

  def discord_emote_image(match, css_class:)
    shortcode = ":#{match[:name]}:"
    extension = match[:animated] == "a" ? "gif" : "png"
    tag.img(src: "https://cdn.discordapp.com/emojis/#{match[:id]}.#{extension}?size=32",
            alt: shortcode, title: shortcode, loading: "lazy", class: css_class)
  end
end
