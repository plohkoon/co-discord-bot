module Memberships
  # Pulls one role off every member of a guild who holds it — the Discord half
  # of deleting a team. Reads the member list over REST (like Backfill) rather
  # than trusting the local memberships, so someone handed the role by hand and
  # never recorded still loses it.
  #
  # One request per holder, which is exactly the burst Discord rate-limits: a
  # 429 waits Discord's own retry_after and tries the same member again. A
  # refusal (403) stops the sweep at once — the bot lacks Manage Roles above
  # the role, so every remaining request would be refused the same way.
  # Idempotent: a re-run only finds whoever still holds the role.
  module StripRole
    Result = Data.define(:removed, :refused)

    # Per member. Discord's retry_after is normally well under a second, so
    # hitting this means something else is wrong — let the job's retry take it.
    MAX_WAITS = 10

    module_function

    def call(guild_id:, role_id:, reason:, api: Discord::BotApi.new, wait: ->(seconds) { sleep(seconds) })
      role = role_id.to_s
      holders = []
      api.each_guild_member(guild_id) do |member|
        holders << member.dig("user", "id") if Array(member["roles"]).map(&:to_s).include?(role)
      end

      removed = 0
      holders.each do |user_id|
        waits = 0
        begin
          api.remove_member_role(guild_id, user_id, role_id, reason: reason)
          removed += 1
        rescue Discord::BotApi::RateLimited => e
          raise if (waits += 1) > MAX_WAITS

          wait.call(e.retry_after)
          retry
        rescue Discord::BotApi::Forbidden
          return Result.new(removed: removed, refused: true)
        rescue Discord::BotApi::NotFound
          # Left the server (or the role was deleted) since the list was read —
          # either way they no longer hold it.
        end
      end

      Result.new(removed: removed, refused: false)
    end
  end
end
