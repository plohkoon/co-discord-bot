module CoBot
  # Message payloads for scheduled-event posts. Both are built around the bare
  # event URL, which Discord unfurls into its native event card — that card
  # tracks the event's live state (including "ended"), so we never repaint it.
  #
  # The announcement is *only* the URL: the card already shows the name, the
  # start time, the location and an Interested button, so any line above it
  # just says the same thing twice. The start post is the exception — its
  # nudge is the entire reason it exists.
  #
  # Pings are opt-in and narrow: `parse` stays empty, so the *only* thing that
  # can ever ping is a role id explicitly listed in `roles` — resolved from the
  # event description by Discord::RoleMentions, which yields mentionable roles
  # only. An `@everyone` typed into an event name or description stays inert.
  module EventMessage
    module_function

    def announcement(event, role_ids: [])
      { "content" => [ mentions(role_ids), event.url ].compact_blank.join("\n"),
        "allowed_mentions" => allowed_mentions(role_ids) }
    end

    def starting(event, role_ids: [])
      nudge = "🔴 **#{event.name}** is starting — come join in!"
      { "content" => "#{[ mentions(role_ids), nudge ].compact_blank.join(" ")}\n#{event.url}",
        "allowed_mentions" => allowed_mentions(role_ids) }
    end

    def mentions(role_ids) = Array(role_ids).map { |id| "<@&#{id}>" }.join(" ")

    def allowed_mentions(role_ids)
      { "parse" => [], "roles" => Array(role_ids).map(&:to_s) }
    end
  end
end
