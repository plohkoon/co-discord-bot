module Commands
  module Team
    module Category
      # Deleting a category keeps its teams — they just become uncategorized
      # (rendered headerless at the end of the directory).
      class Remove < Commands::Base
        include RosterLookups

        description "Remove a roster category (its teams become uncategorized)"
        string :category, "The category to remove", required: true, autocomplete: true
        admin_only!

        def call
          category = TeamCategory.named(option(:category))
          return respond(unknown_choice_message("category", option(:category))) unless category

          category.destroy
          RosterRefreshJob.perform_later(guild_id: current_guild.id)
          respond("✅ Removed category **#{category.name}**. Its teams are now uncategorized.")
        end
      end
    end
  end
end
