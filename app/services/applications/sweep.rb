module Applications
  # Pending-application lifecycle, run periodically by ApplicationSweepJob:
  # escalating reminders in the original review channel at 24h / 3d / 6d, and
  # auto-reject at 7 days (through the same Decide path as the buttons, with
  # decided_by nil = the system). REST-only, so it runs on a queue worker.
  # Caller must set the tenant.
  #
  # reminder_stage records how many reminders have gone out; if the sweep was
  # down across several thresholds, only the latest due reminder is sent.
  class Sweep
    REJECT_AFTER = 7.days
    REMINDERS = [ 24.hours, 3.days, 6.days ].freeze

    def self.call(...) = new(...).call

    def initialize(api: Discord::BotApi.new, now: Time.current)
      @api = api
      @now = now
    end

    def call
      TeamApplication.pending.includes(:team).find_each do |application|
        age = @now - application.created_at
        age >= REJECT_AFTER ? auto_reject(application) : remind(application, age)
      end
    end

    private

    def auto_reject(application)
      result = Decide.call(application: application, decision: :reject, decided_by_discord_id: nil)
      return unless result.status == :ok # someone else decided in the meantime

      application.reload
      refresh_review_message(application)
      notify(application,
             "⏰ The application from #{application.applicant_mention} to **#{application.team.name}** " \
             "was automatically rejected after 7 days without a decision.")
    end

    def remind(application, age)
      due = REMINDERS.count { |threshold| age >= threshold }
      return unless due > application.reminder_stage

      deadline = (application.created_at + REJECT_AFTER).to_i
      delivered = notify(application,
                         "⏰ <@&#{application.team.officer_role_id}> the application from " \
                         "#{application.applicant_mention} to **#{application.team.name}** is still " \
                         "waiting for review — it will be auto-rejected <t:#{deadline}:R>.",
                         ping_officers: true)
      application.update!(reminder_stage: due) if delivered
    end

    # Repaint the original review message like a button decision would
    # (decided embed, Accept/Reject buttons dropped).
    def refresh_review_message(application)
      return unless application.review_channel_id && application.review_message_id

      @api.edit_message(application.review_channel_id, application.review_message_id,
                        "embeds" => [ CoBot::ReviewMessage.decided_embed(application).to_hash ],
                        "components" => CoBot::ReviewMessage.notes_only_view(application).to_a)
    rescue Discord::BotApi::Error => e
      Rails.logger.warn("[sweep] review message refresh failed for application #{application.id}: #{e.class}: #{e.message}")
    end

    # Post in the review channel, replying to the original review message when
    # we have one. Returns true when sent OR permanently unsendable (channel
    # gone) — false only on transient failure, so the reminder retries next run.
    def notify(application, content, ping_officers: false)
      channel_id = application.review_channel_id || application.team.review_channel_id
      return true unless channel_id

      payload = {
        "content" => content,
        "allowed_mentions" => { "parse" => [], "roles" => ping_officers ? [ application.team.officer_role_id.to_s ] : [] }
      }
      if application.review_message_id
        payload["message_reference"] = { "message_id" => application.review_message_id.to_s, "fail_if_not_exists" => false }
      end

      @api.create_message(channel_id, payload)
      true
    rescue Discord::BotApi::NotFound
      true # channel deleted — don't retry forever
    rescue Discord::BotApi::Error => e
      Rails.logger.warn("[sweep] notify failed for application #{application.id}: #{e.class}: #{e.message}")
      false
    end
  end
end
