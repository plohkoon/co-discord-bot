module Applications
  # Park a pending application. The daily digest stops listing it and its 7-day
  # deadline stops running, but the application stays `pending` — so the
  # one-pending-per-person index, the /team apply pre-check and every pending?
  # guard behave exactly as before, and a lead can still Accept or Reject it
  # while parked.
  #
  # Nothing is scheduled or cancelled here. The sweep asks "which applications
  # are pending and unpaused?" each morning, so pausing is just a column and
  # there are no timers left behind to fire on a stale clock.
  #
  # Resuming restarts the clock rather than resuming it: the "waiting N days"
  # count and the 7-day deadline are both measured from timeline_started_at, so
  # an application parked for a month gets a full review window back instead of
  # expiring the moment it wakes up.
  #
  # Shared by the review-message buttons and the web membership page.
  class Pause
    Result = Struct.new(:status, keyword_init: true)

    def self.pause(...) = new(...).pause

    def self.resume(...) = new(...).resume

    def initialize(application:, actor_discord_id: nil)
      @application = application
      @actor = actor_discord_id
    end

    def pause
      @application.with_lock do
        return Result.new(status: :already_decided) unless @application.pending?
        return Result.new(status: :already_paused) if @application.paused?

        @application.update!(paused_at: Time.current, paused_by_discord_id: @actor)
      end

      Result.new(status: :ok)
    end

    def resume
      @application.with_lock do
        return Result.new(status: :already_decided) unless @application.pending?
        return Result.new(status: :not_paused) unless @application.paused?

        @application.update!(paused_at: nil, paused_by_discord_id: nil, timeline_started_at: Time.current)
      end

      Result.new(status: :ok)
    end
  end
end
