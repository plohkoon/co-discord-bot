module Commands
  module Team
    # `/team absence` — member self-service call-out (no gating, like /team
    # apply). Opens a modal to pick the day (+ optional note); the submission
    # lands in Components::AbsenceModal.
    class Absence < Commands::Base
      description "Let your team know you'll miss a raid day"
      string :team, "The team you'll miss", required: true, autocomplete: true

      def call
        team = resolve_team(option(:team))
        return respond("Pick a team from the list.") unless team

        show_modal(title: "Call out — #{team.name}",
                   custom_id: CoBot::CommandRegistry.custom_id("callout", team.id)) do |modal|
          modal.label(label: "Which day? (e.g. 2026-07-26, today, Sat)") do |label|
            label.text_input(style: :short, custom_id: "day", required: true, max_length: 40,
                             placeholder: "today · tomorrow · Sat · 2026-07-26")
          end
          modal.label(label: "Note (optional)") do |label|
            label.text_input(style: :paragraph, custom_id: "note", required: false, max_length: 500,
                             placeholder: "Anything the team should know")
          end
        end
      end

      def autocomplete_team(query)
        current_guild.teams.active.matching(query).limit(25).to_h { |team| [ team.name, team.id.to_s ] }
      end
    end
  end
end
