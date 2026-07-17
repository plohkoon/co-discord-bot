module Commands
  module Team
    # Update a team's name and roster details (category, type + the free-form
    # lines shown by /team roster). Only options actually passed are changed.
    class Edit < Commands::Base
      include RosterLookups

      description "Update a team's name and roster details"
      string :team, "The team to update", required: true, autocomplete: true
      string :name, "New team name (renames the team)"
      string :category, "Roster section header — pick an existing category", autocomplete: true
      string :team_type, "Team type — pick from this server's list", autocomplete: true
      string :emote, "Emoji shown before the team name in the roster (unicode or :name: from this server)"
      string :progression, "Roster line (e.g. Currently 7/9 H)"
      string :requirements, "Roster line (e.g. Req. iLvl - 250+)"
      string :date_and_time, "When the team plays (e.g. Tuesdays 7-10pm CT)"
      string :current_needs, "What the team is looking for (e.g. DPS)"
      integer :position, "Sort order within the category (lower first; Manage Server only)"
      officer_only!

      def call
        team = resolve_team(option(:team))
        return respond("Pick a team from the list.") unless team

        if option(:category)
          category = TeamCategory.named(option(:category))
          return respond(unknown_choice_message("category", option(:category))) unless category

          team.team_category = category
        end

        if option(:team_type)
          team_type = TeamType.named(option(:team_type))
          return respond(unknown_choice_message("team type", option(:team_type))) unless team_type

          team.team_type = team_type
        end

        return unless resolve_emote_onto(team)

        team.name = resolve_text(option(:name).to_s.strip) if option(:name)
        # Position is directory placement relative to OTHER teams — a server
        # layout call, not a team detail, so leads don't get it.
        unless option(:position).nil?
          return respond("⛔ Only **Manage Server** users can change a team's position.") unless admin?

          team.position = option(:position).to_i
        end
        (::Team::ROSTER_FIELDS - [ :emote ]).each do |field|
          team[field] = resolve_text(option(field).to_s.strip) if option(field)
        end

        if team.save
          RosterRefreshJob.perform_later(guild_id: current_guild.id)
          respond("✅ Updated **#{team.name}**. The posted roster refreshes automatically.")
        else
          respond("⚠️ Couldn't update the team: #{team.errors.full_messages.to_sentence}")
        end
      end

      def autocomplete_team(query)
        current_guild.teams.active.matching(query).limit(25).to_h { |team| [ team.name, team.id.to_s ] }
      end
    end
  end
end
