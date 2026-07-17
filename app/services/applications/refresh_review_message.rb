module Applications
  # Repaint the original review message after a decision — decided embed,
  # Accept/Reject buttons dropped — exactly like a button decision does in
  # place. Shared by the web decide flow and the auto-reject sweep. Best
  # effort: a missing message/channel is logged, never raised.
  class RefreshReviewMessage
    def self.call(application, api: Discord::BotApi.new)
      return unless application.review_channel_id && application.review_message_id

      api.edit_message(application.review_channel_id, application.review_message_id,
                       "embeds" => [ CoBot::ReviewMessage.decided_embed(application).to_hash ],
                       "components" => CoBot::ReviewMessage.notes_only_view(application).to_a)
    rescue Discord::BotApi::Error => e
      Rails.logger.warn("[applications] review message refresh failed for application #{application.id}: #{e.class}: #{e.message}")
    end
  end
end
