# Posts the officer review message for a fresh application — enqueued by
# Applications::Submit after its transaction commits, so the Discord modal and
# the public web form produce the identical message (same embed, same
# persistent Accept/Reject/Pause buttons, same stored ids for every later
# repaint) without either surface doing REST in-request or on the gateway
# dispatch thread.
#
# Guards make re-delivery safe: an application that already has its review
# message, or was decided before this ran, posts nothing. A missing channel or
# permission problem is logged, not retried (retrying can't fix it); only
# transient Discord errors retry.
class ReviewMessagePostJob < ApplicationJob
  queue_as :default

  retry_on Discord::BotApi::Error, wait: :polynomially_longer, attempts: 3

  def perform(guild_id:, application_id:)
    guild = Guild.find_by(id: guild_id) or return

    ActsAsTenant.with_tenant(guild) do
      application = TeamApplication.find_by(id: application_id) or next
      next if application.review_message_id.present? # already posted
      next unless application.pending? # decided before we got here — nothing to review

      begin
        CoBot::ReviewMessage.post(team: application.team, application: application)
      rescue Discord::BotApi::NotFound, Discord::BotApi::Forbidden => e
        Rails.logger.warn("[applications] review message post failed for application #{application.id}: #{e.class}: #{e.message}")
      end
    end
  end
end
