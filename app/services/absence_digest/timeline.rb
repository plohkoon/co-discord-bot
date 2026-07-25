# The scheduled morning delivery of one (team, day) absence digest. Unlike the
# application review digest — a daily sweep, because "still waiting" is a live
# query — an absence is anchored to a specific future date, so the job is
# scheduled once when the first call-out for a team-day lands. It reads the
# *live* active set at fire time, so cancellations and late additions land too;
# the durable AbsenceDigest row is the idempotency mechanism.
class AbsenceDigest::Timeline
  DIGEST_HOUR = 8 # local hour to post the morning "who's out today" digest

  # Enqueue the exact-timestamp job for the guild-local morning of digest_on.
  # `in_time_zone` handles DST, and a past fire time (a call-out made after 8am
  # for that same day) simply runs immediately.
  def self.schedule(digest)
    fire = digest.digest_on.in_time_zone(digest.guild.tz).change(hour: DIGEST_HOUR)
    AbsenceDigestJob.set(wait_until: fire).perform_later(guild_id: digest.guild_id, digest_id: digest.id)
  end

  # Post the grouped digest for the day, then mark it sent. `sent?` guards a
  # retry / post-downtime double-fire. An empty active set still marks sent (no
  # message). A vanished channel is swallowed; a transient error propagates so
  # the job retries with the row still pending.
  def self.deliver(digest:, api: Discord::BotApi.new, now: Time.current)
    return if digest.sent?

    team = digest.team
    absences = team.absences.active.on(digest.digest_on).order(:discord_username, :id).to_a
    post(team, absences, api) if absences.any?
    digest.update!(status: :sent, sent_at: now)
  end

  def self.post(team, absences, api)
    channel_id = team.notify_channel_id or return

    api.create_message(channel_id, {
      "content" => build_message(team, absences),
      "allowed_mentions" => { "parse" => [], "roles" => [ team.officer_role_id.to_s ] }
    })
  rescue Discord::BotApi::NotFound
    nil # channel gone — nothing more we can do; the caller still marks it sent
  end
  private_class_method :post

  def self.build_message(team, absences)
    lines = absences.map do |absence|
      absence.note.present? ? "#{absence.mention} — #{absence.note.strip}" : absence.mention
    end
    "<@&#{team.officer_role_id}> 📋 Absences today for **#{team.name}**:\n#{lines.join("\n")}"
  end
  private_class_method :build_message
end
