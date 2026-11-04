module Commands
  module Components
    # The team-proposal modal submission. Saves the proposal, then hands the
    # admin-channel post to TeamProposalPostJob — no REST on the dispatch
    # thread, and a Discord hiccup can't lose the pitch.
    class ProposeTeamModal < Commands::Base
      component :modal, "proposal", params: [ :category_id ]

      def call
        category = TeamCategory.find_by(id: params[:category_id])
        # Defense in depth: proposals may have been switched off while the
        # modal was open.
        return respond("That category isn't taking new team proposals right now.") unless category&.accepting_proposals?

        proposal = TeamProposal.create!(
          team_category: category,
          discord_user_id: current_user_id,
          discord_username: author_name,
          answers: TeamProposal::QUESTIONS.map do |question|
            { "label" => question[:label], "answer" => event.value(question[:key]).to_s.strip }
          end
        )
        TeamProposalPostJob.perform_later(guild_id: current_guild.id, proposal_id: proposal.id)

        respond("✅ Thanks! Your proposal for a new **#{category.name}** team was sent to the server admins.")
      end
    end
  end
end
