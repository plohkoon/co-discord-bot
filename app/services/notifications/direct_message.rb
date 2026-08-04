module Notifications
  # Sends a plain-content DM to a Discord user, best-effort. A closed DM
  # (Forbidden) or a vanished user (NotFound) is a logged no-op — the applicant
  # already got their ephemeral submit ack, so a failed DM is harmless. Mentions
  # never ping ({parse: []}). Transient BotApi::Error propagates so the caller's
  # job can retry. Generic — reused by every DM flow.
  module DirectMessage
    module_function

    # `components` lets a DM carry a button. That matters because a button may
    # open a modal where a modal submit may not, so a follow-up message is the
    # only place a correction flow can live.
    def call(user_id:, content:, components: nil, api: Discord::BotApi.new)
      payload = { "content" => content, "allowed_mentions" => { "parse" => [] } }
      payload["components"] = components.to_a if components
      api.send_dm(user_id, payload)
    rescue Discord::BotApi::Forbidden, Discord::BotApi::NotFound => e
      Rails.logger.info("[notifications] DM to #{user_id} skipped: #{e.class}: #{e.message}")
      nil
    end
  end
end
