module Commands
  module Components
    # The /team apply modal submission.
    class ApplyModal < Commands::Base
      component :modal, "apply", params: [ :team_id ]

      def call
        team = current_guild.teams.find_by(id: params[:team_id])
        return respond("That team no longer exists.") unless team
        # Defense in depth: the team may have closed between opening this modal
        # and submitting it (the roster button/pre-check guard fired earlier).
        return respond(team.resolved_closed_message) unless team.recruiting?

        # Submit enqueues the review-message post (ReviewMessagePostJob) —
        # shared with the web apply page, so both surfaces produce the
        # identical officer message.
        Applications::Submit.call(team: team, event: event)
        respond("✅ Your application to **#{team.name}** was submitted! The team's officers will review it.")
      rescue Applications::Submit::AlreadyMember
        respond("You're already a member of **#{team.name}**.")
      rescue Applications::Submit::DuplicatePending
        respond("You already have a pending application to **#{team.name}**.")
      end
    end
  end
end
