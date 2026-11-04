module Commands
  module Components
    # The "Apply to make a team" button beside a roster category header. Opens
    # the fixed TeamProposal questionnaire; ProposeTeamModal handles the submit.
    class ProposeTeamButton < Commands::Base
      component :button, "proposeteam", params: [ :category_id ]

      def call
        category = TeamCategory.find_by(id: params[:category_id])
        # A stale roster message can outlive the switch being turned off.
        return respond("That category isn't taking new team proposals right now.") unless category&.accepting_proposals?

        show_modal(title: "Start a team — #{category.name}",
                   custom_id: CoBot::CommandRegistry.custom_id("proposal", category.id)) do |modal|
          TeamProposal::QUESTIONS.each do |question|
            modal.label(label: question[:label], description: question[:description]) do |label|
              label.text_input(style: :paragraph, custom_id: question[:key],
                               required: question[:key] != "on_board", max_length: TeamProposal::ANSWER_MAX)
            end
          end
        end
      end
    end
  end
end
