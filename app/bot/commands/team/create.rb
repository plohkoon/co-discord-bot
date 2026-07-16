module Commands
  module Team
    class Create < Commands::Base
      description "Create a team"
      string  :name, "Team name", required: true
      role    :role, "Role granted to team members", required: true
      role    :officer_role, "Role pinged to review applications", required: true
      channel :review_channel, "Channel where applications are posted", required: true, channel_types: [ :text ]
      admin_only!

      def call
        team = current_guild.teams.new(
          name: option(:name).to_s.strip,
          team_role_id: option(:role),
          officer_role_id: option(:officer_role),
          review_channel_id: option(:review_channel)
        )

        if team.save
          team.seed_default_questions!
          respond("✅ Created team **#{team.name}**. Members can now `/team apply`. " \
                  "I added starter application questions — edit them in the dashboard.")
          backfill_existing_members(team)
        else
          respond("⚠️ Couldn't create the team: #{team.errors.full_messages.to_sentence}")
        end
      end

      private

      # Anyone already holding the team role becomes an active member. Runs
      # after the ack — chunking members can take seconds on large servers.
      def backfill_existing_members(team)
        count = Memberships::Backfill.call(team: team, server: server)
        return unless count.positive?

        follow_up("👥 Picked up **#{count}** existing #{"holder".pluralize(count)} of the team role as active #{"member".pluralize(count)}.")
      rescue => e
        Rails.logger.error("[co-bot] member backfill for team #{team.id} failed: #{e.class}: #{e.message}")
      end
    end
  end
end
