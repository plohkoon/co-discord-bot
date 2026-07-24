# Guild activity logging: routes notable events to a guild's configured log
# channel(s). Infrastructure other features call — keep the signature stable.
#
# Does NO network I/O and holds no gateway reference, so it's safe to call from
# the bot, the web app, or a background job. It only fast-checks whether the
# level has a channel and, if so, enqueues GuildLogJob with primitive args; the
# job re-resolves the channel and posts. Best effort — never raises into a
# caller (an invalid level is the one exception: that's a programming error).
#
# Call it AFTER the surrounding DB transaction commits (like Timeline.schedule):
# the queue lives in a separate database.
module GuildLog
  module_function

  def record(guild:, level:, title:, description: nil, fields: [], actor_id: nil, color: nil)
    level = level.to_sym
    raise ArgumentError, "unknown log level #{level.inspect}" unless Guild::LOG_LEVELS.include?(level)
    return if guild.nil?

    # Fast pre-check: skip the enqueue entirely when this level has no channel.
    # The job re-resolves at run time, so config edited between now and then
    # still wins there.
    return if guild.log_channel_id_for(level).nil?

    GuildLogJob.perform_later(
      guild_id: guild.id,
      level: level,
      title: title,
      description: description,
      fields: fields,
      actor_id: actor_id,
      color: color
    )
  end
end
