module RoleRewards
  # Run every rule for one guild: grant the role to newly-qualifying users,
  # and — only for rules with auto_revoke on — strip it from users who no
  # longer qualify.
  #
  # Direction matters: qualification comes from the WoW tables (users first),
  # never from paging the guild's member list. Discord's add-role endpoint
  # 404s for anyone not in the guild, which is the membership filter — a 404
  # is "skip, they may join later", never an error and never a recorded grant.
  #
  # Revoke semantics (opt-in per rule): "no longer qualifies" includes the
  # data going absent — a season reset zeroes M+ scores and starts an empty
  # PvP season, and an unlinked Battle.net account or released character takes
  # its data with it. No longer verifiable → no role. A 404 on removal (they
  # left the server / the role is gone) still clears the grant row, since
  # there is nothing left to revoke.
  #
  # All REST happens outside any DB transaction; each grant/revoke is one call
  # plus one single-row write, so a crash or rate limit resumes cleanly on the
  # next sweep.
  module Evaluate
    module_function

    def call(guild:, api: Discord::BotApi.new)
      ActsAsTenant.with_tenant(guild) do
        RoleReward.order(:id).each { |reward| evaluate(reward, api: api) }
      end
    end

    def evaluate(reward, api:)
      qualifying = reward.qualifying_discord_user_ids
      return if qualifying.nil? # unevaluable right now (see RoleReward) — touch nothing

      granted = reward.role_reward_grants.pluck(:discord_user_id).map(&:to_i)

      (qualifying - granted).each do |discord_user_id|
        case grant(reward, discord_user_id, api: api)
        when :granted then record_grant(reward, discord_user_id)
        when :halt then return
        end
      end

      return unless reward.auto_revoke?

      (granted - qualifying).each do |discord_user_id|
        case revoke(reward, discord_user_id, api: api)
        when :revoked then reward.role_reward_grants.where(discord_user_id: discord_user_id).delete_all
        when :halt then return
        end
      end
    end

    def grant(reward, discord_user_id, api:)
      api.add_member_role(reward.guild_id, discord_user_id, reward.discord_role_id,
                          reason: "co-bot: role reward (#{reward.summary})")
      :granted
    rescue Discord::BotApi::Forbidden => e
      # Missing Manage Roles or the reward role sits above the bot — true for
      # every member, so stop burning calls on this rule.
      Rails.logger.warn("[role_rewards] can't manage role #{reward.discord_role_id} " \
                        "in guild #{reward.guild_id}: #{e.message}")
      :halt
    rescue Discord::BotApi::NotFound
      :skipped # not in this guild (or the role vanished) — retry next sweep
    rescue Discord::BotApi::Error => e
      Rails.logger.warn("[role_rewards] grant failed for user #{discord_user_id} " \
                        "in guild #{reward.guild_id}: #{e.message}")
      :skipped
    end

    def revoke(reward, discord_user_id, api:)
      api.remove_member_role(reward.guild_id, discord_user_id, reward.discord_role_id,
                             reason: "co-bot: role reward no longer met (#{reward.summary})")
      :revoked
    rescue Discord::BotApi::Forbidden => e
      Rails.logger.warn("[role_rewards] can't manage role #{reward.discord_role_id} " \
                        "in guild #{reward.guild_id}: #{e.message}")
      :halt
    rescue Discord::BotApi::NotFound
      :revoked # they left, or the role is gone — nothing to hold a grant row for
    rescue Discord::BotApi::Error => e
      Rails.logger.warn("[role_rewards] revoke failed for user #{discord_user_id} " \
                        "in guild #{reward.guild_id}: #{e.message}")
      :kept # transient — keep the row so the next sweep retries the removal
    end

    def record_grant(reward, discord_user_id)
      reward.role_reward_grants.create!(discord_user_id: discord_user_id, granted_at: Time.current)
    rescue ActiveRecord::RecordNotUnique
      # A concurrent sweep beat us to the row — the role is granted either way.
    end
  end
end
