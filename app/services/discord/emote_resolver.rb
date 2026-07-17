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

    module_function

    def call(guild_id:, input:, api: Discord::BotApi.new)
      cleaned = input.to_s.strip
      return nil if cleaned.blank?
      return cleaned if cleaned.match?(MENTION)

      name = cleaned[SHORTCODE, 1]
      return cleaned unless name # unicode (or plain text) — rendered verbatim

      emoji = api.guild_emojis(guild_id).find { |e| e["name"].to_s.casecmp?(name) }
      raise UnknownEmote, name unless emoji

      "<#{"a" if emoji["animated"]}:#{emoji["name"]}:#{emoji["id"]}>"
    end
  end
end
