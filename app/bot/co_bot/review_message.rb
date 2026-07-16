module CoBot
  # Builds and posts the officer-review message: an embed summarising the
  # applicant + their answers, with persistent Accept/Reject buttons.
  module ReviewMessage
    BRAND  = 0x5865F2
    ACCEPT = 0x57F287
    REJECT = 0xED4245

    module_function

    def post(bot:, team:, application:)
      channel = bot.channel(team.review_channel_id)
      return unless channel

      content = "<@&#{team.officer_role_id}> new application for **#{team.name}**"
      # Only ping the officer role — never @everyone or the applicant.
      allowed = { parse: [], roles: [ team.officer_role_id ] }

      # send_message(content, tts, embed, attachments, allowed_mentions, message_reference, components)
      message = channel.send_message(content, false, pending_embed(team, application), nil, allowed, nil, decision_view(application))
      application.update(review_channel_id: channel.id, review_message_id: message.id)
      message
    end

    def pending_embed(team, application)
      Discordrb::Webhooks::Embed.new(
        title: "Application — #{team.name}",
        description: "From #{application.applicant_mention} (`#{application.discord_username}`)",
        color: BRAND,
        fields: answer_fields(application),
        timestamp: application.created_at
      )
    end

    def decided_embed(application)
      accepted = application.accepted?
      Discordrb::Webhooks::Embed.new(
        title: "Application — #{application.team.name} · #{accepted ? 'Accepted' : 'Rejected'}",
        description: "From #{application.applicant_mention}\n#{decided_line(application)}",
        color: accepted ? ACCEPT : REJECT,
        fields: answer_fields(application),
        timestamp: application.decided_at || application.created_at
      )
    end

    # nil decided_by = the system decided (e.g. the 7-day auto-reject sweep).
    def decided_line(application)
      verb = application.accepted? ? "Accepted" : "Rejected"
      actor = application.decided_by_discord_id
      actor ? "#{verb} by <@#{actor}>" : "#{verb} automatically — no decision within 7 days"
    end

    def decision_view(application)
      view = Discordrb::Webhooks::View.new
      view.row do |row|
        row.button(label: "Accept", style: :success, custom_id: CoBot::CommandRegistry.custom_id("decide", "accept", application.id))
        row.button(label: "Reject", style: :danger,  custom_id: CoBot::CommandRegistry.custom_id("decide", "reject", application.id))
      end
      add_notes_row(view, application)
      view
    end

    # After a decision, keep the notes buttons (drop Accept/Reject).
    def notes_only_view(application)
      view = Discordrb::Webhooks::View.new
      add_notes_row(view, application)
      view
    end

    def add_notes_row(view, application)
      membership_id = application.team_membership_id
      return unless membership_id

      view.row do |row|
        row.button(label: "📝 Add note",   style: :secondary, custom_id: CoBot::CommandRegistry.custom_id("note", membership_id))
        row.button(label: "📋 View notes", style: :secondary, custom_id: CoBot::CommandRegistry.custom_id("notes", membership_id))
      end
    end

    def answer_fields(application)
      application.application_answers.map do |answer|
        Discordrb::Webhooks::EmbedField.new(
          name: answer.question_label.to_s[0, 256].presence || "—",
          value: answer.answer.to_s[0, 1024].presence || "—",
          inline: false
        )
      end
    end
  end
end
