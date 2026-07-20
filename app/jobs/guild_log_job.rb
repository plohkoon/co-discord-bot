# Delivers one guild-log entry (enqueued by GuildLog.record) to the guild's
# configured channel as a color-coded embed. The channel is re-resolved at run
# time, so config changed after enqueue still wins. Logs never ping anyone.
class GuildLogJob < ApplicationJob
  queue_as :default

  # Transient Discord/network errors retry with backoff. NotFound/Forbidden
  # (channel deleted, or the bot can't post there) are swallowed as a logged
  # no-op below — a lost log line must never take down a business action.
  retry_on Discord::BotApi::Error, wait: :polynomially_longer, attempts: 5

  # Fallback accent per level when a caller doesn't pass one.
  DEFAULT_COLORS = { high: 0xFFD166, low: 0x99AAB5 }.freeze

  def perform(guild_id:, level:, title:, description: nil, fields: [], actor_id: nil, color: nil, api: Discord::BotApi.new)
    guild = Guild.find_by(id: guild_id) or return

    ActsAsTenant.with_tenant(guild) do
      channel_id = guild.log_channel_id_for(level) or return # unset since enqueue

      payload = build_payload(level: level, title: title, description: description,
                              fields: fields, actor_id: actor_id, color: color)
      api.create_message(channel_id, payload)
    end
  rescue Discord::BotApi::NotFound => e
    # Covers Forbidden (a subclass): the channel is gone or unpostable. Nothing
    # to retry — drop the log line.
    Rails.logger.warn("[guild_log] delivery skipped for guild #{guild_id}: #{e.class}: #{e.message}")
  end

  private

  def build_payload(level:, title:, description:, fields:, actor_id:, color:)
    embed = {
      "title" => title.to_s,
      "color" => (color || DEFAULT_COLORS.fetch(level.to_sym)),
      "timestamp" => Time.current.iso8601
    }
    embed["description"] = description.to_s if description.present?
    embed["fields"] = embed_fields(fields, actor_id)

    {
      "embeds" => [ embed ],
      # Logs echo mentions (roles, applicants) but must never ping them.
      "allowed_mentions" => { "parse" => [] }
    }
  end

  # Normalize caller-supplied fields (string- or symbol-keyed) and append the
  # actor as its own field when present.
  def embed_fields(fields, actor_id)
    list = Array(fields).map do |f|
      { "name" => (f[:name] || f["name"]).to_s, "value" => (f[:value] || f["value"]).to_s,
        "inline" => !!(f[:inline] || f["inline"]) }
    end
    list << { "name" => "By", "value" => "<@#{actor_id}>", "inline" => true } if actor_id
    list
  end
end
