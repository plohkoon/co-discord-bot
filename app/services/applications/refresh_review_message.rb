module Applications
  # Repaint the original review message, exactly as a button press would in
  # place: the decided embed with Accept/Reject dropped once it's settled, or
  # the live pending/paused embed with its buttons intact while it's still open
  # — so a pause taken on the web shows up in Discord too. Shared by the web
  # decide/pause flows and the auto-reject sweep. Best effort: a missing
  # message/channel is logged, never raised.
  class RefreshReviewMessage
    def self.call(application, api: Discord::BotApi.new)
      return unless application.review_channel_id && application.review_message_id

      embed, view =
        if application.pending?
          [ CoBot::ReviewMessage.pending_embed(application.team, application),
            CoBot::ReviewMessage.decision_view(application) ]
        else
          [ CoBot::ReviewMessage.decided_embed(application),
            CoBot::ReviewMessage.notes_only_view(application) ]
        end

      api.edit_message(application.review_channel_id, application.review_message_id,
                       "embeds" => [ embed.to_hash ], "components" => view.to_a)
    rescue Discord::BotApi::Error => e
      Rails.logger.warn("[applications] review message refresh failed for application #{application.id}: #{e.class}: #{e.message}")
    end
  end
end
