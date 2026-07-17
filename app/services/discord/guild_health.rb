module Discord
  # Proactive permission health check for one guild, run web-side over REST so
  # the result is fresh when an admin is actively fixing their server. Checks
  # the same invariants Memberships::RoleManager enforces at action time:
  # Manage Roles, team roles exist, and the bot's highest role sits above them.
  #
  # Returns a plain hash (cache-safe across code reloads):
  #   { status: :ok | :issues | :removed | :unknown,
  #     problems: [{ summary:, action: }, ...],
  #     checked_at: Time }
  #
  # :removed also stamps guild.removed_at — a second detection path alongside
  # the gateway's server_delete. :unknown means the check itself failed (no
  # token, network error); callers should stay quiet rather than warn.
  class GuildHealth
    ADMINISTRATOR = 1 << 3

    # Role-level permissions the bot needs (mirrors BOT_INVITE_PERMISSIONS).
    # Channel-level overwrites can still deny these locally; this catches the
    # common case of an invite that under-granted.
    REQUIRED_PERMISSIONS = {
      "Manage Roles"  => 1 << 28, # grant/revoke team roles
      "View Channels" => 1 << 10,
      "Send Messages" => 1 << 11, # review messages, roster, reminders
      "Embed Links"   => 1 << 14  # review message embeds
    }.freeze
    MANAGE_ROLES = REQUIRED_PERMISSIONS.fetch("Manage Roles")

    CACHE_TTL = 60.seconds

    def self.call(guild:, teams:, api: BotApi.new)
      Rails.cache.fetch(cache_key(guild.id), expires_in: CACHE_TTL) do
        new(guild: guild, teams: teams, api: api).call
      end
    end

    # Bust the cache so the next page load re-checks immediately.
    def self.expire(guild) = Rails.cache.delete(cache_key(guild.id))

    def self.cache_key(guild_id) = "discord/guild_health/#{guild_id}"

    def initialize(guild:, teams:, api:)
      @guild = guild
      @teams = teams
      @api = api
    end

    def call
      return result(:unknown) unless @api.configured?

      roles_by_id = @api.guild_roles(@guild.id).index_by { |r| r["id"].to_s }
      member = @api.guild_member(@guild.id, @api.bot_user_id)
      problems = check(roles_by_id, member)
      result(problems.empty? ? :ok : :issues, problems)
    rescue BotApi::NotFound
      @guild.mark_removed!
      result(:removed)
    rescue => e
      Rails.logger.warn("[web] guild health check failed for #{@guild.id}: #{e.class}: #{e.message}")
      result(:unknown)
    end

    private

    def check(roles_by_id, member)
      bot_roles = roles_by_id.values_at(*Array(member["roles"]).map(&:to_s)).compact
      everyone = roles_by_id[@guild.id.to_s] # the @everyone role's id == guild id
      permissions = [ everyone, *bot_roles ].compact.reduce(0) { |acc, r| acc | r["permissions"].to_i }
      highest_position = bot_roles.map { |r| r["position"].to_i }.max || 0

      problems = []
      unless permissions.anybits?(ADMINISTRATOR)
        REQUIRED_PERMISSIONS.each do |name, bit|
          next if permissions.anybits?(bit)

          problems << { summary: "co-bot is missing the #{name} permission.",
                        action: "Grant #{name} to the co-bot role in Server Settings → Roles, or re-run the invite link to re-authorize." }
        end
      end

      @teams.each do |team|
        role = roles_by_id[team.team_role_id.to_s]
        if role.nil?
          problems << { summary: "The Discord role for team “#{team.name}” no longer exists.",
                        action: "Recreate the role in Discord, or archive the team." }
        elsif role["position"].to_i >= highest_position
          problems << { summary: "co-bot's highest role is below “#{role["name"]}”, so it can't assign the “#{team.name}” team role.",
                        action: "Drag the co-bot role above “#{role["name"]}” in Server Settings → Roles." }
        end
      end
      problems
    end

    def result(status, problems = [])
      { status: status, problems: problems, checked_at: Time.current }
    end
  end
end
