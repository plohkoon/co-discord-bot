# Fired by the runner's member_join listener (which does no REST on the
# gateway thread — it only enqueues). Grants the team role for any active
# memberships the joiner already holds: the payoff of "apply from the web,
# get accepted, then join the server". Expected 404s (joined and left again)
# are handled inside JoinReconcile; only transient Discord errors retry.
class MemberJoinReconcileJob < ApplicationJob
  queue_as :default

  retry_on Discord::BotApi::Error, wait: :polynomially_longer, attempts: 3

  def perform(guild_id:, discord_user_id:)
    guild = Guild.installed.find_by(id: guild_id) or return

    Memberships::JoinReconcile.call(guild: guild, discord_user_id: discord_user_id)
  end
end
