module Commands
  module Guild
    module Category
      class Add < Commands::Base
        include RosterLookups

        description "Add a roster category"
        string  :name, "Category name (directory section header, e.g. PvE Teams ⚔️)", required: true
        integer :position, "Sort order in the directory (lower first; default: last)"
        string  :about, "Text shown under the header (multiple paragraphs: use the web dashboard)"
        boolean :proposals, "Show an \"Apply to make a team\" button beside the header (default: off)"
        admin_only!

        def call
          category = TeamCategory.new(name: resolve_text(option(:name).to_s.strip), position: option(:position))
          category.about = resolve_text(option(:about).to_s.strip) if option(:about)
          category.proposals_enabled = option(:proposals) unless option(:proposals).nil?

          if category.save
            # Unfiltered rosters show every category, so a new one appears
            # there straight away (with its about and button).
            RosterRefreshJob.perform_later(guild_id: current_guild.id) if RosterPost.exists?
            respond("✅ Added category **#{category.name}**. Teams can pick it in `/guild create` or `/team edit`." +
                    proposals_note(category))
          else
            respond("⚠️ Couldn't add the category: #{category.errors.full_messages.to_sentence}")
          end
        end

        private

        def proposals_note(category)
          return "" unless category.proposals_enabled? && !current_guild.team_proposals_enabled?

          " The **Apply to make a team** button appears once a team-proposals channel is set on the web dashboard."
        end
      end
    end
  end
end
