# The one recurring job behind application review reminders. Runs hourly and
# does a guild's work once the guild's OWN clock has reached DIGEST_HOUR — a
# single daily UTC cron would land at a different local time in every server.
#
# "Has reached", not "is exactly at": the per-team date stamp is what makes the
# day idempotent, so a run that misses its hour (worker restart, queue backlog)
# is picked up by the next hourly pass instead of skipping the guild until
# tomorrow. Late is better than never for a review nudge.
#
# Every guild gets swept even when its teams have the digest switched off: the
# 7-day auto-reject rides along on the same pass, so turning off the digest
# silences the notification without stranding applications forever.
class ReviewDigestSweepJob < ApplicationJob
  queue_as :default

  # Guild-local hour. One after the absence digest so the two don't land on top
  # of each other in servers that share a channel.
  DIGEST_HOUR = 9

  retry_on Discord::BotApi::Error, wait: :polynomially_longer, attempts: 5

  def perform(now: Time.current, api: Discord::BotApi.new)
    Guild.installed.find_each do |guild|
      local = now.in_time_zone(guild.tz)
      next if local.hour < DIGEST_HOUR

      ActsAsTenant.with_tenant(guild) do
        Team.active.find_each do |team|
          Applications::ReviewDigest.deliver(team: team, on: local.to_date, api: api, now: now)
        end
      end
    end
  end
end
