module CoBot
  # Builds and posts the officer-review message: an embed summarising the
  # applicant + their answers, with persistent Accept/Reject buttons.
  module ReviewMessage
    BRAND  = 0x5865F2
    ACCEPT = 0x57F287
    REJECT = 0xED4245
    PAUSED = 0xFEE75C

    module_function

    # Post the review message over REST — the one path both surfaces share
    # (the Discord modal and the public web form both enqueue
    # ReviewMessagePostJob after Applications::Submit commits). REST rather
    # than the gateway so a process with no gateway connection (web, jobs) can
    # send it; the buttons' custom_ids are restart-safe Components ids, so
    # they work identically on a REST-posted message.
    def post(team:, application:, api: Discord::BotApi.new)
      channel_id = team.review_channel_id or return
      message = api.create_message(channel_id, rest_payload(team, application))
      application.update(review_channel_id: channel_id, review_message_id: message["id"])
      message
    end

    # The raw create-message payload: officer ping + pending embed + the
    # persistent Accept/Reject/Pause buttons. Only the officer role may ping —
    # never @everyone or the applicant.
    def rest_payload(team, application)
      {
        "content" => "<@&#{team.officer_role_id}> new application for **#{team.name}**",
        "embeds" => [ pending_embed(team, application).to_hash ],
        "components" => decision_view(application).to_a,
        "allowed_mentions" => { "parse" => [], "roles" => [ team.officer_role_id.to_s ] }
      }
    end

    def pending_embed(team, application)
      paused = application.paused?
      Discordrb::Webhooks::Embed.new(
        title: "Application — #{team.name}#{paused ? " · Paused" : ""}",
        description: [ "From #{application.applicant_mention} (`#{application.discord_username}`)",
                       (paused_line(application) if paused) ].compact.join("\n"),
        color: paused ? PAUSED : BRAND,
        fields: raider_fields(application) + answer_fields(application),
        timestamp: application.created_at
      )
    end

    def paused_line(application)
      actor = application.paused_by_discord_id
      "⏸️ Paused#{actor ? " by <@#{actor}>" : ""} — no reminders and no 7-day auto-reject until it's resumed."
    end

    def decided_embed(application)
      accepted = application.accepted?
      Discordrb::Webhooks::Embed.new(
        title: "Application — #{application.team.name} · #{accepted ? 'Accepted' : 'Rejected'}",
        description: "From #{application.applicant_mention}\n#{decided_line(application)}",
        color: accepted ? ACCEPT : REJECT,
        fields: raider_fields(application) + answer_fields(application),
        timestamp: application.decided_at || application.created_at
      )
    end

    # nil decided_by = the system decided (e.g. the 7-day auto-reject sweep).
    def decided_line(application)
      verb = application.accepted? ? "Accepted" : "Rejected"
      actor = application.decided_by_discord_id
      actor ? "#{verb} by <@#{actor}>" : "#{verb} automatically — no decision within 7 days"
    end

    # Accept/Reject plus the park button — Pause while it's running, Resume once
    # it's parked. Accept and Reject stay live either way, so pausing never
    # blocks a decision.
    def decision_view(application)
      view = Discordrb::Webhooks::View.new
      view.row do |row|
        row.button(label: "Accept", style: :success, custom_id: CoBot::CommandRegistry.custom_id("decide", "accept", application.id))
        row.button(label: "Reject", style: :danger,  custom_id: CoBot::CommandRegistry.custom_id("decide", "reject", application.id))
        if application.paused?
          row.button(label: "▶️ Resume", style: :primary, custom_id: CoBot::CommandRegistry.custom_id("pause", "resume", application.id))
        else
          row.button(label: "⏸️ Pause", style: :secondary, custom_id: CoBot::CommandRegistry.custom_id("pause", "pause", application.id))
        end
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
        # A link button, not an interaction: Discord opens it directly, so the
        # full report costs the bot nothing. Omitted when APP_URL isn't set —
        # a bot job has no request to infer a host from, and a broken link is
        # worse than no link.
        url = detail_url(application)
        row.button(label: "🔎 Show more detail", style: :link, url: url) if url
      end
    end

    # The applicant's page on the web app, where the full history lives.
    def detail_url(application)
      origin = ENV["APP_URL"].presence&.chomp("/") or return nil
      return nil unless application.team_membership_id

      "#{origin}/guilds/#{application.guild_id}/teams/#{application.team_id}" \
        "/memberships/#{application.team_membership_id}"
    end

    # The character digest, above the answers because it's the thing an officer
    # scans first. Absent entirely when the team doesn't collect a character —
    # an empty field would just be noise for those teams.
    def raider_fields(application)
      body = Applications::RaiderSummary.body(application) or return []

      [ Discordrb::Webhooks::EmbedField.new(
        name: Applications::RaiderSummary::HEADING, value: body.to_s[0, 1024], inline: false
      ) ]
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
