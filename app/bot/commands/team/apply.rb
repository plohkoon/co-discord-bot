module Commands
  module Team
    class Apply < Commands::Base
      description "Apply to join a team"
      string :team, "The team you want to apply to", required: true, autocomplete: true

      def call
        team = resolve_team(option(:team))
        return respond("Pick a team from the list.") unless team
        return respond("You're already a member of **#{team.name}**.") if member_of?(team)
        return respond("You already have a pending application to **#{team.name}**.") if pending_for?(team)

        questions = team.application_questions.ordered.to_a
        return respond("**#{team.name}** has no application questions set up yet.") if questions.empty?

        show_modal(title: "Apply — #{team.name}", custom_id: CoBot::CommandRegistry.custom_id("apply", team.id)) do |modal|
          questions.each do |question|
            modal.label(label: question.label) do |label|
              label.text_input(
                style: question.paragraph? ? :paragraph : :short,
                custom_id: "q:#{question.id}",
                required: question.required,
                min_length: question.min_length,
                max_length: question.max_length,
                placeholder: question.placeholder.presence
              )
            end
          end
        end
      end

      def autocomplete_team(query)
        current_guild.teams.active.matching(query).limit(25).to_h { |team| [ team.name, team.id.to_s ] }
      end

      private

      def member_of?(team)  = team.team_memberships.active.where(discord_user_id: current_user_id).exists?
      def pending_for?(team) = team.team_memberships.pending.where(discord_user_id: current_user_id).exists?
    end
  end
end
