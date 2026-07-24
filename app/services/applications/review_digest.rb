module Applications
  # One team's daily review digest — the single source of truth for everything
  # time-based about a pending application.
  #
  # There are no per-application scheduled jobs. Once a day (see
  # ReviewDigestSweepJob, which calls this at the guild-local digest hour) this
  # reads the live rows, retires anything past its 7-day deadline, and posts one
  # grouped "still waiting" message instead of scattering nudges through the
  # day. Because nothing is scheduled ahead of time, nothing can go stale:
  # pausing an application simply takes it out of tomorrow's query.
  #
  # The immediate review message an application posts on arrival is NOT part of
  # this — that one is the workflow, not a nag, and still fires on submit.
  class ReviewDigest
    REJECT_AFTER = 7.days

    def self.deliver(...) = new(...).deliver

    def initialize(team:, on:, api: Discord::BotApi.new, now: Time.current)
      @team = team
      @on = on   # the guild-local date this run is for
      @api = api
      @now = now
    end

    # Returns true when it did today's work, false when today was already done.
    def deliver
      return false if @team.last_review_digest_on == @on # retry / double-fire

      overdue.each { |application| auto_reject(application) }
      post_digest
      # Stamped last: if the post raises, the job retries and re-runs the whole
      # day (the auto-rejections are idempotent — Decide's claim already won).
      @team.update!(last_review_digest_on: @on)
      true
    end

    private

    def channel_id = @team.review_channel_id

    # Live, unpaused, undecided. A paused application is invisible to every part
    # of this: no deadline, no digest line.
    def pending
      @pending ||= @team.team_applications.pending.where(paused_at: nil).order(:created_at).to_a
    end

    def deadline_for(application) = application.timeline_start + REJECT_AFTER

    def overdue = pending.select { |application| @now >= deadline_for(application) }

    def waiting_days(application) = ((@now - application.timeline_start) / 1.day).floor

    # Old enough to be worth mentioning. A team that reviews same-day doesn't
    # want yesterday's arrivals listed back at them the next morning, so the
    # threshold defaults to 1 — the review message already announced them.
    def listed
      (pending - overdue).select { |application| waiting_days(application) >= @team.review_digest_after_days }
    end

    # Same system-decision path as before (decided_by_discord_id: nil), so the
    # membership archives and the review message repaints to "Rejected".
    def auto_reject(application)
      result = Decide.call(application: application, decision: :reject, decided_by_discord_id: nil)
      RefreshReviewMessage.call(application.reload, api: @api) if result.status == :ok
    end

    # Expiries during this guild-local day, re-read from the rows rather than
    # remembered, so a retry after a failed post still reports them.
    #
    # decided_by_discord_id: nil means "the system decided", but the sweep isn't
    # the only system decider — Memberships::Archive rejects pending
    # applications the same way when a role is pulled. Only a rejection at or
    # past the application's own deadline is an expiry.
    def retired_today
      start = @on.in_time_zone(@team.guild.tz).beginning_of_day
      @team.team_applications.rejected.where(decided_by_discord_id: nil, decided_at: start..)
           .to_a.count { |application| application.decided_at >= deadline_for(application) }
    end

    def post_digest
      return unless @team.review_digest? && channel_id

      retired = retired_today
      return if listed.empty? && retired.zero?
      return if still_on_screen?

      message = @api.create_message(channel_id, {
        "content" => build_message(retired),
        "allowed_mentions" => { "parse" => [], "roles" => @team.remind_ping? ? [ @team.officer_role_id.to_s ] : [] }
      })
      @team.update!(last_review_digest_message_id: message["id"]) if message.is_a?(Hash) && message["id"]
    rescue Discord::BotApi::NotFound
      nil # channel gone or unreadable — the run still counts as done
    end

    # Don't stack digests on each other: if yesterday's is still the newest
    # thing in the channel, nobody has engaged and a fresh copy adds nothing.
    # A new application breaks this by itself — its review message lands after
    # the digest — so the sweep starts posting again the moment there's news.
    def still_on_screen?
      marker = @team.last_review_digest_message_id
      return false unless marker

      newest = Array(@api.channel_messages(channel_id, limit: 1)).first
      newest && newest["id"].to_i == marker.to_i
    rescue Discord::BotApi::NotFound
      false # no Read Message History — post rather than go silent
    end

    def build_message(retired)
      lines = listed.map do |application|
        days = waiting_days(application)
        "• #{application.applicant_mention} (`#{application.discord_username}`) — waiting " \
          "#{days} #{"day".pluralize(days)}, decide by <t:#{deadline_for(application).to_i}:R>"
      end
      lines << "⏰ #{retired} #{"application".pluralize(retired)} auto-rejected after 7 days without a decision." if retired.positive?

      header = if listed.any?
        "<@&#{@team.officer_role_id}> 📋 **#{@team.name}** — #{listed.size} #{"application".pluralize(listed.size)} waiting for review:"
      else
        "<@&#{@team.officer_role_id}> 📋 **#{@team.name}**"
      end
      [ header, *lines ].join("\n")
    end
  end
end
