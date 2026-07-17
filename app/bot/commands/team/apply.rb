module Commands
  module Team
    class Apply < Commands::Base
      include Commands::ApplyFlow

      description "Apply to join a team"
      string :team, "The team you want to apply to", required: true, autocomplete: true

      def call
        team = resolve_team(option(:team))
        return respond("Pick a team from the list.") unless team

        start_application(team)
      end

      def autocomplete_team(query)
        current_guild.teams.active.matching(query).limit(25).to_h { |team| [ team.name, team.id.to_s ] }
      end
    end
  end
end
