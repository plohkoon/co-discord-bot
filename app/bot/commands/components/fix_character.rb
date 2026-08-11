module Commands
  module Components
    # "Fix character" on the DM an applicant gets when their character couldn't
    # be found — opens a modal to retype it.
    #
    # A button MAY open a modal; a modal submit may not (Discord: response type
    # MODAL is "not available for MODAL_SUBMIT"). That asymmetry is the whole
    # reason correction lives on a follow-up message rather than being handled
    # inline when the application is submitted.
    #
    # Deliberately free text rather than a picker of characters we know about:
    # someone applying on a freshly levelled alt would find themselves unable to
    # name it, and being unable to correct a typo is worse than the typo.
    class FixCharacter < Commands::Base
      component :button, "fixchar", params: [ :application_id ], in_dm: true

      # A DM has no server, so the tenant comes from the application itself.
      def self.guild_from_params(params)
        application = ::TeamApplication.find_by(id: params[:application_id]) or return nil

        ::Guild.find_by(id: application.guild_id)
      end

      def call
        application = find_application or return respond("That application is no longer open.")

        show_modal(title: "Character — #{application.team.name}",
                   custom_id: CoBot::CommandRegistry.custom_id("fixcharmodal", application.id)) do |modal|
          modal.label(label: "Your character (Name-Realm)") do |label|
            label.text_input(style: :short, custom_id: "character", required: true, max_length: 64,
                             # Pre-filled with what they typed so a one-letter
                             # slip is a one-letter fix.
                             value: application.character_input.to_s[0, 64],
                             placeholder: "Thrall-Sargeras")
          end
        end
      end

      private

      # Only the applicant, and only while it's still open — a decided
      # application's character is part of the record.
      def find_application
        application = ::TeamApplication.find_by(id: params[:application_id])
        return nil unless application&.pending?
        return nil unless application.discord_user_id.to_s == event.user.id.to_s

        application
      end
    end
  end
end
