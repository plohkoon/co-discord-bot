# Moves a guild's event posts when its events channel is set, changed or
# cleared. Enqueued by Guild's own commit hook, so every surface that can edit
# the setting is covered.
#
# Two halves, in order:
#
#   1. Vacate the old channel. Posts there are deleted rather than abandoned —
#      once an event's row points somewhere else, nothing would ever clean them
#      up (GuildEventCleanupJob deletes by the event's recorded channel_id), so
#      "relinquishing" the old channel means permanent litter.
#   2. Fill the new one from Discord's own list of events, oldest first. This
#      is the only path that reaches events created while the feature was off:
#      GuildEvents::Sync ignores everything until a channel exists, so a guild
#      configuring one for the first time has no rows at all.
#
# Posting runs inline (perform_now) rather than through the queue, because the
# ordering is the point — queue workers would race and shuffle the back
# catalogue. Every post is still guarded by its own job, so a retry after a
# rate limit resumes rather than double-posting.
class GuildEventsResyncJob < ApplicationJob
  queue_as :default

  retry_on Discord::BotApi::Error, wait: :polynomially_longer, attempts: 5

  # Discord's status values for events that haven't finished — the only ones
  # worth posting. Its list endpoint drops completed/canceled events, so this
  # is belt-and-braces.
  LIVE_STATUSES = [ 1, 2 ].freeze

  def perform(guild_id:, previous_channel_id: nil, api: Discord::BotApi.new)
    guild = Guild.installed.find_by(id: guild_id) or return

    ActsAsTenant.with_tenant(guild) do
      vacate(api, previous_channel_id) if previous_channel_id.present?
      backfill(guild, api) if guild.events_channel_id.present?
    end
  end

  private

  # Delete everything we posted in the channel we're leaving. A terminal event
  # is finished for good once its posts are gone, so it's marked cleaned up;
  # the rest are left blank for the backfill to re-post.
  def vacate(api, channel_id)
    GuildEvent.live.where(channel_id: channel_id).find_each do |event|
      event.message_ids.each { |message_id| delete(api, channel_id, message_id) }
      event.update!(announcement_message_id: nil, start_message_id: nil, channel_id: nil,
                    cleaned_up_at: event.terminal? ? Time.current : nil)
    end
  end

  # Snowflakes encode their creation time, so ascending id *is* oldest-first by
  # creation date — no timestamp on the event object needed.
  def backfill(guild, api)
    payloads = api.guild_scheduled_events(guild.id)
                  .select { |payload| LIVE_STATUSES.include?(payload["status"].to_i) }
                  .sort_by { |payload| payload["id"].to_i }

    payloads.each do |payload|
      event = GuildEvents::Sync.call(guild: guild, payload: payload, publish: false) or next

      GuildEventAnnounceJob.perform_now(guild_id: guild.id, guild_event_id: event.id, api: api)
      # An event already under way gets the same pair of posts it would have
      # had if the channel had been configured all along.
      GuildEventStartJob.perform_now(guild_id: guild.id, guild_event_id: event.id, api: api) if event.active?
    end
  end

  def delete(api, channel_id, message_id)
    api.delete_message(channel_id, message_id)
  rescue Discord::BotApi::NotFound
    nil # already gone, or the old channel was deleted outright
  end
end
