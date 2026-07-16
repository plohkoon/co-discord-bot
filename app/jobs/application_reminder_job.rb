# Scheduled by Applications::Timeline at exact reminder timestamps (24h/3d/6d
# after submission). Short-circuits if the application was decided, the stage
# was already sent, or a later stage is due (collapse after worker downtime).
class ApplicationReminderJob < ApplicationJob
  queue_as :default

  retry_on Discord::BotApi::Error, wait: :polynomially_longer, attempts: 5

  def perform(guild_id:, application_id:, stage:)
    guild = Guild.find_by(id: guild_id) or return

    ActsAsTenant.with_tenant(guild) do
      application = TeamApplication.find_by(id: application_id) or next
      Applications::Timeline.remind(application: application, stage: stage)
    end
  end
end
