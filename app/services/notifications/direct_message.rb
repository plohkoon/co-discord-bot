module Notifications
  # Sends a plain-content DM to a Discord user, best-effort. A closed DM
  # (Forbidden) or a vanished user (NotFound) is a logged no-op — the applicant
  # already got their ephemeral submit ack, so a failed DM is harmless. Mentions
  # never ping ({parse: []}). Transient BotApi::Error propagates so the caller's
  # job can retry. Generic — reused by every DM flow.
  module DirectMessage
    module_function

    def call(user_id:, content:, api: Discord::BotApi.new)
      api.send_dm(user_id, { "content" => content, "allowed_mentions" => { "parse" => [] } })
    rescue Discord::BotApi::Forbidden, Discord::BotApi::NotFound => e
      Rails.logger.info("[notifications] DM to #{user_id} skipped: #{e.class}: #{e.message}")
      nil
    end
  end
end
