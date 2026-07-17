module Discord
  # Normalizes a team-emote input into something Discord will actually render
  # in API-sent message content (the roster). The :name: shorthand is expanded
  # client-side by the message composer, never by the server, so bots must
  # post the full mention form for custom emoji:
  #
  #   "⚔️"              -> kept verbatim (unicode renders as-is)
  #   ":swordguy:"      -> "<:swordguy:123>" looked up in the guild's emoji list
  #   "<:swordguy:123>" -> kept verbatim (escape hatch, incl. other servers'
  #                        emoji the bot can see; <a:...:id> for animated)
  #
  # Raises UnknownEmote for a :name: that isn't in the guild, so callers can
  # reject it instead of posting literal ":name:" text.
  module EmoteResolver
    class UnknownEmote < StandardError
      attr_reader :name

      def initialize(name)
        @name = name
        super("no emote named :#{name}: in this guild")
      end
    end

    SHORTCODE = /\A:([a-zA-Z0-9_~]{2,}):\z/
    MENTION   = /\A<a?:[a-zA-Z0-9_~]+:\d+>\z/
    # Inline scan: existing mentions match first (and pass through) so their
    # inner :name: is never re-resolved; group 1 captures candidate shortcodes.
    TOKEN     = /<a?:[a-zA-Z0-9_~]+:\d+>|:([a-zA-Z0-9_~]{2,}):/

    module_function

    def call(guild_id:, input:, api: Discord::BotApi.new)
      cleaned = input.to_s.strip
      return nil if cleaned.blank?
      return cleaned if cleaned.match?(MENTION)

      name = cleaned[SHORTCODE, 1]
      return cleaned unless name # unicode (or plain text) — rendered verbatim

      emoji = emojis_for(guild_id, api)[name.downcase]
      raise UnknownEmote, name unless emoji

      mention(emoji)
    end

    # Lenient inline form for free-typed text (names, roster lines): every
    # :name: matching a guild emote becomes its mention form; unknown
    # shortcodes stay as typed (free text legitimately contains colons —
    # "7:30:00", "Req: iLvl"), as do unicode and existing mentions. An API
    # failure returns the text unchanged — it never blocks a save.
    def resolve_text(guild_id:, input:, api: Discord::BotApi.new)
      text = input.to_s
      return input unless text.match?(TOKEN)

      emojis = emojis_for(guild_id, api)
      text.gsub(TOKEN) do |match|
        name = Regexp.last_match(1)
        emoji = name && emojis[name.downcase]
        emoji ? mention(emoji) : match
      end
    rescue Discord::BotApi::Error
      input
    end

    def mention(emoji) = "<#{"a" if emoji["animated"]}:#{emoji["name"]}:#{emoji["id"]}>"

    # {downcased name => emoji hash}, briefly cached like the role/channel
    # pickers — one save may resolve several fields.
    def emojis_for(guild_id, api)
      Rails.cache.fetch("discord/guild_emojis/#{guild_id}", expires_in: 60.seconds) do
        api.guild_emojis(guild_id).index_by { |emoji| emoji["name"].to_s.downcase }
      end
    end
  end
end
