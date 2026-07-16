module Commands
  module Components
    # The /team apply modal submission.
    class ApplyModal < Commands::Base
      component :modal, "apply", params: [ :team_id ]

      def call
        team = current_guild.teams.find_by(id: params[:team_id])
        return respond("That team no longer exists.") unless team

        application = Applications::Submit.call(team: team, event: event)
        respond("✅ Your application to **#{team.name}** was submitted! The team's officers will review it.")
        CoBot::ReviewMessage.post(bot: event.bot, team: team, application: application)
      rescue Applications::Submit::AlreadyMember
        respond("You're already a member of **#{team.name}**.")
      rescue Applications::Submit::DuplicatePending
        respond("You already have a pending application to **#{team.name}**.")
      end
    end
  end
end
