module Commands
  module Components
    # Note modal submission (from the "Add note" button).
    class NoteModal < Commands::Base
      component :modal, "note_form", params: [ :membership_id ]

      def call
        membership = TeamMembership.find_by(id: params[:membership_id])
        return respond("That membership no longer exists.") unless membership
        return respond("Only officers can add notes.") unless officer_for?(membership.team)

        body = event.value("body").to_s.strip
        return respond("Note was empty.") if body.blank?

        membership.membership_notes.create!(author_discord_id: current_user_id, author_username: author_name, body: body)
        respond("📝 Note added.\n\n#{render_notes(membership)}")
      end
    end
  end
end
