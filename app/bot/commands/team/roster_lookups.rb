module Commands
  module Team
    # Shared option plumbing for /team create|edit: category and team type are
    # picked from the guild's curated lists (managed on the web guild page),
    # never created on the fly. Autocomplete offers the lists; typed values
    # that match nothing are rejected with a pointer to the dashboard.
    module RosterLookups
      def autocomplete_category(query)
        TeamCategory.ordered.where("name LIKE ?", "%#{query.to_s.strip}%").limit(25).to_h { |c| [ c.name, c.name ] }
      end

      def autocomplete_team_type(query)
        TeamType.ordered.where("name LIKE ?", "%#{query.to_s.strip}%").limit(25).to_h { |t| [ t.name, t.name ] }
      end

      def unknown_choice_message(kind, value)
        "⚠️ This server has no #{kind} named **#{value}** — pick one from the autocomplete list. " \
        "Manage Server users can edit the #{kind} list in the web dashboard."
      end
    end
  end
end
