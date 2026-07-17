module Commands
  module Team
    class Create < Commands::Base
      include RosterLookups

      description "Create a team"
      string  :name, "Team name", required: true
      role    :role, "Role granted to team members", required: true
      role    :officer_role, "Role pinged to review applications", required: true
      channel :review_channel, "Channel where applications are posted", required: true, channel_types: [ :text ]
      string  :category, "Roster section header — pick an existing category", autocomplete: true
      string  :team_type, "Team type — pick from this server's list", autocomplete: true
      string  :emote, "Emoji shown before the team name in the roster (unicode or :name: from this server)"
      string  :progression, "Roster line (e.g. Currently 7/9 H)"
      string  :requirements, "Roster line (e.g. Req. iLvl - 250+)"
      string  :date_and_time, "When the team plays (e.g. Tuesdays 7-10pm CT)"
      string  :current_needs, "What the team is looking for (e.g. DPS)"
      integer :position, "Sort order within the category (lower first)"
      admin_only!

      def call
        category = TeamCategory.named(option(:category))
        return respond(unknown_choice_message("category", option(:category))) if option(:category).present? && category.nil?

        team_type = TeamType.named(option(:team_type))
        return respond(unknown_choice_message("team type", option(:team_type))) if option(:team_type).present? && team_type.nil?

        team = current_guild.teams.new(
          name: option(:name).to_s.strip,
          team_role_id: option(:role),
          officer_role_id: option(:officer_role),
          review_channel_id: option(:review_channel),
          team_category: category,
          team_type: team_type,
          position: option(:position).to_i,
          **(::Team::ROSTER_FIELDS - [ :emote ]).index_with { |field| option(field).to_s.strip.presence }
        )
        return unless resolve_emote_onto(team)

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
    end
  end
end
