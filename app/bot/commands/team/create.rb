module Commands
  module Team
    class Create < Commands::Base
      description "Create a team"
      string  :name, "Team name", required: true
      role    :role, "Role granted to team members", required: true
      role    :officer_role, "Role pinged to review applications", required: true
      channel :review_channel, "Channel where applications are posted", required: true, channel_types: [ :text ]
      string  :category, "Roster section header (e.g. PvE Teams ⚔️)", autocomplete: true
      string  :team_type, "Roster line (e.g. Heroic Team)"
      string  :progression, "Roster line (e.g. Currently 7/9 H)"
      string  :requirements, "Roster line (e.g. Req. iLvl - 250+)"
      string  :date_and_time, "When the team plays (e.g. Tuesdays 7-10pm CT)"
      string  :current_needs, "What the team is looking for (e.g. DPS)"
      admin_only!

      def call
        team = current_guild.teams.new(
          name: option(:name).to_s.strip,
          team_role_id: option(:role),
          officer_role_id: option(:officer_role),
          review_channel_id: option(:review_channel),
          team_category: TeamCategory.locate(option(:category)),
          **::Team::ROSTER_FIELDS.index_with { |field| option(field).to_s.strip.presence }
        )

        if team.save
          team.seed_default_questions!
          respond("✅ Created team **#{team.name}**. Members can now `/team apply`. " \
                  "I added starter application questions — edit them in the dashboard.")
          # Existing role holders become members in the background; the job
          # reports the count via an interaction follow-up (REST, no gateway).
          TeamBackfillJob.perform_later(
            guild_id: current_guild.id,
            team_id: team.id,
            application_id: event.interaction.application_id,
            interaction_token: event.interaction.token
          )
        else
          respond("⚠️ Couldn't create the team: #{team.errors.full_messages.to_sentence}")
        end
      end

      def autocomplete_category(query)
        TeamCategory.ordered.where("name LIKE ?", "%#{query.to_s.strip}%").limit(25).to_h { |c| [ c.name, c.name ] }
      end
    end
  end
end
