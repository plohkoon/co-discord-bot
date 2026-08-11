# Evaluate WoW role-reward rules — hourly across every installed guild that
# has any (config/recurring.yml), and immediately for one guild when an admin
# adds a rule (so they see it work). Granting is REST via the bot token, so
# this runs fine from a worker with no gateway connection.
class RoleRewardSweepJob < ApplicationJob
  queue_as :default

  def perform(guild_id: nil, api: Discord::BotApi.new)
    return unless api.configured?

    guilds(guild_id).each { |guild| RoleRewards::Evaluate.call(guild: guild, api: api) }
  end

  private

  # Only guilds that actually have rules — the sweep shouldn't touch the rest.
  def guilds(guild_id)
    scope = Guild.installed
    return scope.where(id: guild_id) if guild_id

    scope.where(id: ActsAsTenant.without_tenant { RoleReward.distinct.pluck(:guild_id) })
  end
end
