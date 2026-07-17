module Commands
  module Team
    # Update a team's roster details (category + the free-form lines shown by
    # /team roster). Only options actually passed are changed.
    class Edit < Commands::Base
      description "Update a team's roster details"
      string :team, "The team to update", required: true, autocomplete: true
      string :category, "Roster section header (e.g. PvE Teams ⚔️)", autocomplete: true
      string :team_type, "Roster line (e.g. Heroic Team)"
      string :progression, "Roster line (e.g. Currently 7/9 H)"
      string :requirements, "Roster line (e.g. Req. iLvl - 250+)"
      string :date_and_time, "When the team plays (e.g. Tuesdays 7-10pm CT)"
      string :current_needs, "What the team is looking for (e.g. DPS)"
      integer :position, "Sort order within the category (lower first)"
      officer_only!

      def call
        team = resolve_team(option(:team))
        return respond("Pick a team from the list.") unless team

        team.team_category = TeamCategory.locate(option(:category)) if option(:category)
        team.position = option(:position).to_i unless option(:position).nil?
        ::Team::ROSTER_FIELDS.each do |field|
          team[field] = option(field).to_s.strip if option(field)
        end

        if team.save
          TeamRosterRefreshJob.perform_later(guild_id: current_guild.id, team_id: team.id)
          respond("✅ Updated **#{team.name}**. The posted roster refreshes automatically.")
        else
          respond("⚠️ Couldn't update the team: #{team.errors.full_messages.to_sentence}")
        end
      end

      def autocomplete_team(query)
        current_guild.teams.active.matching(query).limit(25).to_h { |team| [ team.name, team.id.to_s ] }
      end

      def autocomplete_category(query)
        TeamCategory.ordered.where("name LIKE ?", "%#{query.to_s.strip}%").limit(25).to_h { |c| [ c.name, c.name ] }
      end
    end
  end
end
