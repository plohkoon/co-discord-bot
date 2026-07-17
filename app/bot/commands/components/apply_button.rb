module Commands
  module Components
    # The "Apply" button under each team in the /team roster directory. Opens
    # the same modal as /team apply; Components::ApplyModal handles the submit.
    class ApplyButton < Commands::Base
      include Commands::ApplyFlow

      component :button, "applyto", params: [ :team_id ]

      def call
        team = current_guild.teams.active.find_by(id: params[:team_id])
        return respond("That team no longer exists.") unless team

        start_application(team)
      end
    end
  end
end
