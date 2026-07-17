module Commands
  module Team
    module Type
      class Add < Commands::Base
        description "Add a team type"
        string  :name, "Team type name (e.g. Heroic Team)", required: true
        integer :position, "Sort order in pickers (lower first; default: last)"
        admin_only!

        def call
          team_type = TeamType.new(name: option(:name).to_s.strip, position: option(:position))
          if team_type.save
            respond("✅ Added team type **#{team_type.name}**. Teams can pick it in `/team create|edit`.")
          else
            respond("⚠️ Couldn't add the team type: #{team_type.errors.full_messages.to_sentence}")
          end
        end
      end
    end
  end
end
