module Applications
  # The scheduled lifecycle of one pending application, enqueued at submit time
  # as exact-timestamp Solid Queue jobs: officer reminders at 24h / 3d / 6d and
  # auto-reject at 7 days. Every handler short-circuits if the application was
  # decided in the meantime, so stale jobs are no-ops — Decide's row-lock claim
  # means an officer's click and the auto-reject can never both win.
  #
  # reminder_stage records the last reminder sent. If the worker was down
  # across several thresholds, the overdue jobs all fire together on recovery;
  # the "only the latest due stage sends" guard collapses them into one.
  class Timeline
    REJECT_AFTER = 7.days
    REMINDERS = [ 24.hours, 3.days, 6.days ].freeze

    # Called by Submit right after the application is committed.
    def self.schedule(application)
      REMINDERS.each_with_index do |offset, index|
        ApplicationReminderJob.set(wait_until: application.created_at + offset)
                              .perform_later(guild_id: application.guild_id, application_id: application.id, stage: index + 1)
      end
      ApplicationAutoRejectJob.set(wait_until: application.created_at + REJECT_AFTER)
                              .perform_later(guild_id: application.guild_id, application_id: application.id)
    end

    def self.remind(application:, stage:, api: Discord::BotApi.new, now: Time.current)
      new(application, api).remind(stage, now)
    end

    def self.auto_reject(application:, api: Discord::BotApi.new)
      new(application, api).auto_reject
    end

    def initialize(application, api)
      @application = application
      @api = api
    end

    def remind(stage, now)
      return unless @application.pending?
      return if @application.reminder_stage >= stage # already sent (job retry / duplicate)

      due = REMINDERS.count { |threshold| now - @application.created_at >= threshold }
      return if due > stage # a later reminder is also due — its job sends instead

      deadline = (@application.created_at + REJECT_AFTER).to_i
      notify("⏰ <@&#{team.officer_role_id}> the application from #{@application.applicant_mention} " \
             "to **#{team.name}** is still waiting for review — it will be auto-rejected <t:#{deadline}:R>.",
             ping_officers: true)
      @application.update!(reminder_stage: stage)
    end

    def auto_reject
      result = Decide.call(application: @application, decision: :reject, decided_by_discord_id: nil)
      return unless result.status == :ok # already decided — stale job

      @application.reload
      refresh_review_message
      begin
        notify("⏰ The application from #{@application.applicant_mention} to **#{team.name}** " \
               "was automatically rejected after 7 days without a decision.")
      rescue Discord::BotApi::Error => e
        # The rejection itself is committed; the notice is best-effort.
        Rails.logger.warn("[timeline] auto-reject notice failed for application #{@application.id}: #{e.class}: #{e.message}")
      end
    end

    private

    def team = @application.team

    # Repaint the original review message like a button decision would
    # (decided embed, Accept/Reject buttons dropped).
    def refresh_review_message
      return unless @application.review_channel_id && @application.review_message_id

      @api.edit_message(@application.review_channel_id, @application.review_message_id,
                        "embeds" => [ CoBot::ReviewMessage.decided_embed(@application).to_hash ],
                        "components" => CoBot::ReviewMessage.notes_only_view(@application).to_a)
    rescue Discord::BotApi::Error => e
      Rails.logger.warn("[timeline] review message refresh failed for application #{@application.id}: #{e.class}: #{e.message}")
    end

    # Post in the review channel, replying to the original review message when
    # we have one. A deleted channel is swallowed (permanently unsendable);
    # transient API errors propagate so the job's retry_on takes over.
    def notify(content, ping_officers: false)
      channel_id = @application.review_channel_id || team.review_channel_id
      return unless channel_id

      payload = {
        "content" => content,
        "allowed_mentions" => { "parse" => [], "roles" => ping_officers ? [ team.officer_role_id.to_s ] : [] }
      }
      if @application.review_message_id
        payload["message_reference"] = { "message_id" => @application.review_message_id.to_s, "fail_if_not_exists" => false }
      end

      @api.create_message(channel_id, payload)
    rescue Discord::BotApi::NotFound
      nil
    end
  end
end
