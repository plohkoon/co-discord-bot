# Scheduled by Applications::Timeline for exactly 7 days after submission.
# Short-circuits if an officer decided first (Decide's row-lock claim).
class ApplicationAutoRejectJob < ApplicationJob
  queue_as :default

  retry_on Discord::BotApi::Error, wait: :polynomially_longer, attempts: 5

  def perform(guild_id:, application_id:)
    guild = Guild.find_by(id: guild_id) or return

    ActsAsTenant.with_tenant(guild) do
      application = TeamApplication.find_by(id: application_id) or next
      Applications::Timeline.auto_reject(application: application)
    end
  end
end
