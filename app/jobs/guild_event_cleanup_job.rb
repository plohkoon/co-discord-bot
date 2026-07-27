# Removes every post co-bot made for an event, an hour after it ended (or
# immediately when the event itself was deleted). Scheduled at an exact
# timestamp by GuildEvents::Sync — never a sweep.
#
# Idempotent: an already-cleaned event is a no-op, and each message that's
# already gone is skipped rather than retried.
class GuildEventCleanupJob < ApplicationJob
  queue_as :default

  retry_on Discord::BotApi::Error, wait: :polynomially_longer, attempts: 5

  def perform(guild_id:, guild_event_id:, api: Discord::BotApi.new, now: Time.current)
    guild = Guild.find_by(id: guild_id) or return

    ActsAsTenant.with_tenant(guild) do
      event = GuildEvent.live.find_by(id: guild_event_id) or next
      # A revived event (SCHEDULED again after a cancel) keeps its posts —
      # this fired for a state it's no longer in.
      next unless event.terminal?

      event.message_ids.each { |message_id| delete(api, event.channel_id, message_id) }
      event.update!(announcement_message_id: nil, start_message_id: nil, cleaned_up_at: now)
    end
  end

  private

  def delete(api, channel_id, message_id)
    return if channel_id.blank?

    api.delete_message(channel_id, message_id)
  rescue Discord::BotApi::NotFound
    nil # deleted by hand, or the channel is gone
  end
end
