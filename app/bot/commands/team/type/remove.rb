module Commands
  module Team
    module Type
      # Deleting a type keeps its teams — they just lose the type line.
      class Remove < Commands::Base
        include RosterLookups

        description "Remove a team type (its teams keep everything else)"
        string :team_type, "The team type to remove", required: true, autocomplete: true
        admin_only!

        def call
          team_type = TeamType.named(option(:team_type))
          return respond(unknown_choice_message("team type", option(:team_type))) unless team_type

          team_type.destroy
          RosterRefreshJob.perform_later(guild_id: current_guild.id)
          respond("✅ Removed team type **#{team_type.name}**.")
        end
      end
    end
  end
end
