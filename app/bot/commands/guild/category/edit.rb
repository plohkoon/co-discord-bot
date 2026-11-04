module Commands
  module Guild
    module Category
      # Rename/reorder a category, or change its about text and "Apply to make
      # a team" button; the change lands in any posted roster.
      class Edit < Commands::Base
        include RosterLookups

        # Typed into :about to remove the text (a slash option can't be blanked).
        CLEAR = "none".freeze

        description "Edit a roster category"
        string  :category, "The category to edit", required: true, autocomplete: true
        string  :name, "New name"
        integer :position, "New sort order in the directory (lower first)"
        string  :about, "Text shown under the header (\"none\" clears; multiple paragraphs: use the web dashboard)"
        boolean :proposals, "Show an \"Apply to make a team\" button beside the header"
        admin_only!

        def call
          category = TeamCategory.named(option(:category))
          return respond(unknown_choice_message("category", option(:category))) unless category

          category.name = resolve_text(option(:name).to_s.strip) if option(:name)
          category.position = option(:position).to_i unless option(:position).nil?
          if option(:about)
            about = option(:about).to_s.strip
            category.about = about.casecmp?(CLEAR) ? nil : resolve_text(about)
          end
          category.proposals_enabled = option(:proposals) unless option(:proposals).nil?

          if category.save
            RosterRefreshJob.perform_later(guild_id: current_guild.id)
            respond("✅ Updated category **#{category.name}**#{proposals_note(category)}. " \
                    "The posted roster refreshes automatically.")
          else
            respond("⚠️ Couldn't update the category: #{category.errors.full_messages.to_sentence}")
          end
        end

        private

        def proposals_note(category)
          return "" unless category.saved_change_to_proposals_enabled?
          return " — team proposals turned off" unless category.proposals_enabled?
          return " — team proposals turned on" if current_guild.team_proposals_enabled?

          " — team proposals turned on, but the button only appears once a team-proposals channel " \
            "is set on the web dashboard"
        end
      end
    end
  end
end
