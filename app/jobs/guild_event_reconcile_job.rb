# Backstop for the gateway: re-reads a scheduled event over REST and runs it
# back through the same state machine. Scheduled just after each of the event's
# own start/end timestamps, because Discord's *automatic* status flips (an
# external event goes ACTIVE at its start time and COMPLETED at its end time on
# its own) can't be relied on to arrive as a gateway dispatch — and a
# disconnect drops them regardless.
#
# Carries no state of its own: whatever Discord says now is applied, so running
# it twice, late, or against an unchanged event costs one REST call.
class GuildEventReconcileJob < ApplicationJob
  queue_as :default

  retry_on Discord::BotApi::Error, wait: :polynomially_longer, attempts: 5

  def perform(guild_id:, discord_event_id:, api: Discord::BotApi.new)
    guild = Guild.find_by(id: guild_id) or return

    begin
      payload = api.guild_scheduled_event(guild_id, discord_event_id)
    rescue Discord::BotApi::NotFound
      # Gone from Discord entirely (deleted, or the bot lost the guild) — its
      # card is a dead link now, so pull our posts.
      return GuildEvents::Sync.deleted(guild: guild, discord_event_id: discord_event_id)
    end

    GuildEvents::Sync.call(guild: guild, payload: payload)
  end
end
