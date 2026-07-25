module Commands
  module Components
    # The Pause / Resume button on the review message — parks an application so
    # it stops nagging and never auto-rejects, until a lead picks it back up.
    class Pause < Commands::Base
      component :button, "pause", params: [ :action, :application_id ]

      def call
        application = current_guild.team_applications.find_by(id: params[:application_id])
        return respond("That application no longer exists.") unless application
        return respond("Only **#{application.team.name}** officers can review this application.") unless officer_for?(application.team)

        resuming = params[:action] == "resume"
        result = if resuming
          Applications::Pause.resume(application: application)
        else
          Applications::Pause.pause(application: application, actor_discord_id: current_user_id)
        end

        case result.status
        when :ok
          repaint(application.reload)
        when :already_decided
          respond("This application was already handled by someone else.")
        else
          # Someone else pressed the same button first — the message they're
          # looking at is stale, so repaint it rather than complain.
          repaint(application.reload)
        end
      end

      private

      def repaint(application)
        update_message(embeds: [ CoBot::ReviewMessage.pending_embed(application.team, application) ],
                       components: CoBot::ReviewMessage.decision_view(application))
      end
    end
  end
end
