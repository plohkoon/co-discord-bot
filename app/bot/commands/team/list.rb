module Commands
  module Team
    class List < Commands::Base
      description "List this server's teams"

      def call
        teams = current_guild.teams.active.order(:name)
        return respond("No teams yet. An admin can create one with `/team create`.") if teams.empty?

        lines = teams.map do |team|
          "• **#{team.name}** — <@&#{team.team_role_id}> · #{team.team_memberships.active.count} members · #{team.team_memberships.pending.count} pending"
        end
        respond("**Teams in #{server.name}**\n#{lines.join("\n")}")
      end
    end
  end
end
