module Commands
  module Team
    module Type
      # Rename/reorder a team type; renames land in any posted roster.
      class Edit < Commands::Base
        include RosterLookups

        description "Rename or reorder a team type"
        string  :team_type, "The team type to edit", required: true, autocomplete: true
        string  :name, "New name"
        integer :position, "New sort order in pickers (lower first)"
        admin_only!

        def call
          team_type = TeamType.named(option(:team_type))
          return respond(unknown_choice_message("team type", option(:team_type))) unless team_type

          team_type.name = option(:name).to_s.strip if option(:name)
          team_type.position = option(:position).to_i unless option(:position).nil?

          if team_type.save
            RosterRefreshJob.perform_later(guild_id: current_guild.id)
            respond("✅ Updated team type **#{team_type.name}**. The posted roster refreshes automatically.")
          else
            respond("⚠️ Couldn't update the team type: #{team_type.errors.full_messages.to_sentence}")
          end
        end
      end
    end
  end
end
