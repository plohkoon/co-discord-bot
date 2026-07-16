module Commands
  module Components
    # "📋 View notes" button → ephemeral list.
    class ViewNotes < Commands::Base
      component :button, "notes", params: [ :membership_id ]

      def call
        membership = TeamMembership.find_by(id: params[:membership_id])
        return respond("That membership no longer exists.") unless membership
        return respond("Only officers can view notes.") unless officer_for?(membership.team)

        respond(render_notes(membership))
      end
    end
  end
end
