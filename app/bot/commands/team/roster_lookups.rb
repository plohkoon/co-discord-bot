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

      # Inline emote resolution for free-typed text options (names, roster
      # lines): known :name: shortcodes become mentions so they render in the
      # roster; unknown ones stay as typed. Never errors.
      def resolve_text(value)
        Discord::EmoteResolver.resolve_text(guild_id: current_guild.id, input: value)
      end

      # Normalizes the :emote option (:name: -> <:name:id> via the guild's
      # emoji list; unicode and full mentions pass through). Unlike the inline
      # fields, this standalone field MUST resolve — a broken heading emote is
      # worse than an error. Responds with the failure and returns false when
      # it can't be resolved, so callers can `return unless resolve_emote_onto(team)`.
      def resolve_emote_onto(team)
        return true unless option(:emote)

        team.emote = Discord::EmoteResolver.call(guild_id: current_guild.id, input: option(:emote))
        true
      rescue Discord::EmoteResolver::UnknownEmote => e
        respond("⚠️ This server has no emote named `:#{e.name}:` — check the name, or paste the full `<:name:id>` form.")
        false
      rescue Discord::BotApi::Error
        respond("⚠️ Couldn't look up this server's emotes right now — try again in a moment.")
        false
      end
    end
  end
end
