module Commands
  module Components
    # "📝 Add note" button → open the note modal.
    class AddNote < Commands::Base
      component :button, "note", params: [ :membership_id ]

      def call
        membership = TeamMembership.find_by(id: params[:membership_id])
        return respond("That membership no longer exists.") unless membership
        return respond("Only officers can add notes.") unless officer_for?(membership.team)

        show_modal(title: "Add note — #{membership.discord_username}",
                   custom_id: CoBot::CommandRegistry.custom_id("note_form", membership.id)) do |modal|
          modal.label(label: "Note (officers only)") do |label|
            label.text_input(style: :paragraph, custom_id: "body", required: true,
                             max_length: 2000, placeholder: "Visible only to officers and leads")
          end
        end
      end
    end
  end
end
