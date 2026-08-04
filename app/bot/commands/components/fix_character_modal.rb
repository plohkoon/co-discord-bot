module Commands
  module Components
    # The corrected character, submitted from the DM's "Fix character" modal.
    #
    # Resolution is handed to the same job the original application used, so a
    # correction behaves identically to a first attempt: it claims the
    # character, sets it as the team's active one, and repaints the review
    # message. Including when it fails again — which sends another DM with
    # another button, so a second typo is no more of a dead end than the first.
    class FixCharacterModal < Commands::Base
      component :modal, "fixcharmodal", params: [ :application_id ], in_dm: true

      def self.guild_from_params(params)
        application = ::TeamApplication.find_by(id: params[:application_id]) or return nil

        ::Guild.find_by(id: application.guild_id)
      end

      def call
        application = find_application or return respond("That application is no longer open.")

        input = event.value("character").to_s.strip
        return respond("Give it as Name-Realm, like `Thrall-Sargeras`.") if input.blank?

        # Cleared so the summary reads "Loading…" rather than keeping the old
        # failure on screen while this is looked up again.
        application.update!(character_input: input, character_resolved_at: nil)
        Applications::RefreshReviewMessage.call(application)
        ApplicationCharacterJob.perform_later(application_id: application.id,
                                              guild_id: application.guild_id)

        respond("Thanks — looking up **#{input}** now. If it's still not found I'll message you again.")
      end

      private

      def find_application
        application = ::TeamApplication.find_by(id: params[:application_id])
        return nil unless application&.pending?
        return nil unless application.discord_user_id.to_s == event.user.id.to_s

        application
      end
    end
  end
end
