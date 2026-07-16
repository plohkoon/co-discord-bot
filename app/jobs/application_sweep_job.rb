# Recurring (config/recurring.yml): reminders for pending applications and the
# 7-day auto-reject, per guild. See Applications::Sweep for the actual policy.
class ApplicationSweepJob < ApplicationJob
  queue_as :default

  def perform
    Guild.installed.find_each do |guild|
      ActsAsTenant.with_tenant(guild) { Applications::Sweep.call }
    rescue => e
      Rails.logger.error("[jobs] application sweep failed for guild #{guild.id}: #{e.class}: #{e.message}")
    end
  end
end
