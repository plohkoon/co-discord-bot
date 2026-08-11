module Discord
  # Is this Discord user currently a member of this guild? Answered live over
  # REST with the bot token (GET /guilds/:id/members/:user_id — 404 means not a
  # member), so someone who just accepted an invite only has to reload the
  # public apply page instead of signing in again. Cached briefly; definitive
  # answers only — a failed check (no token, network error, bot lacks access)
  # falls back to the caller's snapshot (the session's member-guild ids) rather
  # than being cached as "no".
  #
  # Follows Discord::GuildHealth's shape for web-side REST use.
  class GuildMembership
    CACHE_TTL = 45.seconds

    def self.call(guild_id:, user_id:, api: BotApi.new, fallback: -> { false })
      return fallback.call unless api.configured?

      Rails.cache.fetch(cache_key(guild_id, user_id), expires_in: CACHE_TTL) do
        begin
          api.guild_member(guild_id, user_id)
          true
        rescue BotApi::Forbidden
          # The bot can't see the guild (kicked / missing access) — that says
          # nothing about the user, so escape the cache block and fall back.
          raise
        rescue BotApi::NotFound
          false
        end
      end
    rescue BotApi::Error => e
      Rails.logger.warn("[web] membership check failed for user #{user_id} in guild #{guild_id}: #{e.class}: #{e.message}")
      fallback.call
    end

    def self.cache_key(guild_id, user_id) = "discord/guild_membership/#{guild_id}/#{user_id}"

    # Bust after a "just joined — check again" style action if one is ever added.
    def self.expire(guild_id, user_id) = Rails.cache.delete(cache_key(guild_id, user_id))
  end
end
