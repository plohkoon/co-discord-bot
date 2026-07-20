# Fires at the guild-local morning of a (team, day) to post the grouped "who's
# out today" digest. Enqueued at exact timestamps by AbsenceDigest::Timeline —
# never a cron sweep. Idempotent via AbsenceDigest#sent? (a retry or
# post-downtime double-fire is a no-op).
class AbsenceDigestJob < ApplicationJob
  queue_as :default

  retry_on Discord::BotApi::Error, wait: :polynomially_longer, attempts: 5

  def perform(guild_id:, digest_id:, api: Discord::BotApi.new)
    guild = Guild.find_by(id: guild_id) or return

    ActsAsTenant.with_tenant(guild) do
      digest = AbsenceDigest.find_by(id: digest_id) or next
      AbsenceDigest::Timeline.deliver(digest: digest, api: api)
    end
  end
end
