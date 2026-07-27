module Discord
  # Pulls role pings out of free text — specifically a scheduled event's
  # description, which Discord itself treats as inert plain text (no
  # autocomplete, no ping). A lead types "@Raid Team" there and co-bot turns it
  # into a real ping on the message *it* posts.
  #
  # Matched against the guild's live role list rather than a pattern, because
  # role names contain spaces ("Raid Team" is one role, not "@Raid" + "Team").
  # Longest name wins, so "@Raid Team Lead" never resolves to "Raid Team".
  #
  # Only ever returns roles Discord already lets anyone mention:
  #
  #   * non-mentionable roles are skipped (rather than posting a mention that
  #     would silently render as plain text unless the bot holds Mention All
  #     Roles) — the guild's own setting stays the source of truth,
  #   * @everyone / @here are never resolvable, so nobody can mass-ping the
  #     server by naming a role in an event description.
  #
  # The description text itself is never echoed into a message — only the ids
  # found in it — so unmatched "@whoever" text can't leak into a post either.
  module RoleMentions
    # Pasted-in mention form; honored when it points at a mentionable role.
    MENTION = /<@&(\d+)>/
    # Names that must never resolve, whatever the guild calls its roles.
    RESERVED = %w[everyone here].freeze

    module_function

    # @return [Array<String>] mentionable role ids, in order of first
    #   appearance. Empty for blank text, no matches, or an API failure —
    #   a ping is a nice-to-have and never blocks the post.
    def call(guild_id:, text:, api: Discord::BotApi.new)
      body = text.to_s
      return [] if body.blank?

      roles = mentionable_roles(guild_id, api)
      return [] if roles.empty?

      body.scan(token(roles)).filter_map do |mention_id, name|
        mention_id && roles.value?(mention_id) ? mention_id : roles[name&.downcase]
      end.uniq
    end

    # Downcased name => id, for roles anyone is allowed to mention. The
    # @everyone role shares the guild's id and is filtered by name too.
    def mentionable_roles(guild_id, api)
      api.guild_roles(guild_id).each_with_object({}) do |role, map|
        next unless role["mentionable"]

        name = role["name"].to_s.delete_prefix("@")
        next if name.blank? || RESERVED.include?(name.downcase)
        next if role["id"].to_s == guild_id.to_s

        map[name.downcase] = role["id"].to_s
      end
    rescue Discord::BotApi::Error => e
      Rails.logger.warn("[co-bot] role lookup failed for guild #{guild_id}: #{e.class}: #{e.message}")
      {}
    end

    # Longest name first so the greediest role wins; the trailing guard stops
    # "@Raiders" from matching a shorter "Raid" role and leaving "ers" behind,
    # and the leading one keeps "someone@Raid" from counting as a mention.
    def token(roles)
      names = roles.keys.sort_by { |name| -name.length }.map { |name| Regexp.escape(name) }
      /#{MENTION.source}|(?<![[:alnum:]_])@(#{names.join("|")})(?![[:alnum:]_])/i
    end
  end
end
