module Commands
  module Team
    module Category
      # Rename/reorder a category; the change lands in any posted roster.
      class Edit < Commands::Base
        include RosterLookups

        description "Rename or reorder a roster category"
        string  :category, "The category to edit", required: true, autocomplete: true
        string  :name, "New name"
        integer :position, "New sort order in the directory (lower first)"
        admin_only!

        def call
          category = TeamCategory.named(option(:category))
          return respond(unknown_choice_message("category", option(:category))) unless category

          category.name = resolve_text(option(:name).to_s.strip) if option(:name)
          category.position = option(:position).to_i unless option(:position).nil?

          if category.save
            RosterRefreshJob.perform_later(guild_id: current_guild.id)
            respond("✅ Updated category **#{category.name}**. The posted roster refreshes automatically.")
          else
            respond("⚠️ Couldn't update the category: #{category.errors.full_messages.to_sentence}")
          end
        end
      end
    end
  end
end
