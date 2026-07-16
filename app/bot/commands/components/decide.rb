module Commands
  module Components
    # Accept/Reject buttons on the review message.
    class Decide < Commands::Base
      component :button, "decide", params: [ :decision, :application_id ]

      def call
        application = current_guild.team_applications.find_by(id: params[:application_id])
        return respond("That application no longer exists.") unless application
        return respond("Only **#{application.team.name}** officers can review this application.") unless officer_for?(application.team)

        result = Applications::Decide.call(
          application: application,
          decision: params[:decision],
          decided_by_discord_id: current_user_id,
          role_granter: ->(_app) { Memberships::RoleManager.grant(bot: event.bot, server: server, team: application.team, discord_user_id: application.discord_user_id) }
        )

        case result.status
        when :already_decided
          respond("This application was already handled by someone else.")
        when :error
          respond("⚠️ #{result.error}")
        else
          update_message(embeds: [ CoBot::ReviewMessage.decided_embed(application.reload) ],
                         components: CoBot::ReviewMessage.notes_only_view(application))
        end
      end
    end
  end
end
