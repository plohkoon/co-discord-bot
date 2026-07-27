module GuildEvents
  # The state machine behind scheduled-event mirroring. Takes a raw Discord
  # guild scheduled event payload (from the gateway or a REST re-fetch),
  # upserts the local row, and enqueues whatever the transition calls for.
  #
  # Does NO network I/O and holds no gateway reference — it runs on discordrb's
  # dispatch thread, so posting is left to jobs (same doctrine as GuildLog).
  # Every side effect is guarded by a stored id or timestamp, which makes a
  # re-delivered gateway event or a backstop re-fetch a no-op.
  class Sync
    # How long our posts stick around after the event ends. Discord's own event
    # card flips to an ended state at that moment, so the delay leaves that
    # visible for a beat before everything disappears.
    CLEANUP_DELAY = 1.hour
    # Backstops fire just *after* the moment they're covering, so Discord has
    # had a chance to flip the status itself.
    BACKSTOP_GRACE = 1.minute

    class << self
      # `publish: false` mirrors the event without queueing any posting — used
      # by the backfill, which posts inline so a guild's whole back catalogue
      # lands in creation order instead of racing across queue workers.
      def call(guild:, payload:, now: Time.current, publish: true)
        return unless guild&.events_channel_id
        return if payload["id"].blank?

        ActsAsTenant.with_tenant(guild) do
          event = GuildEvent.find_or_initialize_by(discord_event_id: payload["id"].to_i)
          apply(event, payload)
          event.ended_at ||= now if event.terminal?
          event.save!

          schedule_backstops(event, now)
          publish(event, now) if publish
          event
        end
      end

      # GUILD_SCHEDULED_EVENT_DELETE: the event object is gone, so its card
      # would render as a dead link — clean up now rather than after the usual
      # grace period.
      def deleted(guild:, discord_event_id:, now: Time.current)
        return unless guild

        ActsAsTenant.with_tenant(guild) do
          event = GuildEvent.live.find_by(discord_event_id: discord_event_id) or return
          event.update!(status: :canceled, ended_at: event.ended_at || now)
          GuildEventCleanupJob.perform_later(guild_id: guild.id, guild_event_id: event.id)
          event
        end
      end

      private

      def apply(event, payload)
        event.name = payload["name"].to_s
        # Kept current on every update so a description edited before the event
        # starts still decides who the start post pings.
        event.description = payload["description"].presence
        event.status = STATUSES.fetch(payload["status"].to_i, :scheduled)
        event.scheduled_start_time = parse_time(payload["scheduled_start_time"])
        event.scheduled_end_time = parse_time(payload["scheduled_end_time"])
      end

      STATUSES = { 1 => :scheduled, 2 => :active, 3 => :completed, 4 => :canceled }.freeze

      def parse_time(value) = value.present? ? Time.zone.parse(value.to_s) : nil

      def publish(event, now)
        return if event.cleaned_up?

        # A never-announced event that's already over gets no post at all —
        # announcing something finished, only to delete it an hour later, is
        # just noise.
        GuildEventAnnounceJob.perform_later(guild_id: event.guild_id, guild_event_id: event.id) if
          !event.announced? && !event.terminal?

        GuildEventStartJob.perform_later(guild_id: event.guild_id, guild_event_id: event.id) if
          event.active? && !event.start_posted?

        return unless event.terminal? && event.message_ids.any?

        GuildEventCleanupJob.set(wait_until: (event.ended_at || now) + CLEANUP_DELAY)
                            .perform_later(guild_id: event.guild_id, guild_event_id: event.id)
      end

      # Gateway delivery of Discord's *automatic* start/end transitions isn't
      # something to bet the feature on (and a disconnect drops them outright),
      # so each timestamp also gets an exact-time job that re-reads the event
      # over REST. Re-enqueued whenever the schedule moves; the reconcile is
      # idempotent, so an orphaned backstop from an old time is harmless.
      def schedule_backstops(event, now)
        return if event.terminal?
        return unless event.saved_change_to_id? ||
                      event.saved_change_to_scheduled_start_time? ||
                      event.saved_change_to_scheduled_end_time?

        [ event.scheduled_start_time, event.scheduled_end_time ].compact.each do |at|
          next if at < now

          GuildEventReconcileJob.set(wait_until: at + BACKSTOP_GRACE)
                                .perform_later(guild_id: event.guild_id, discord_event_id: event.discord_event_id)
        end
      end
    end
  end
end
