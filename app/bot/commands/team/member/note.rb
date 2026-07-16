module Commands
  module Team
    module Member
      class Note < Commands::Base
        include Commands::MemberCommand
        description "Add an officer-only note to a member"
        string :note, "The note (officers only)", required: true

        def call
          membership = resolve_membership or return
          membership.membership_notes.create!(
            author_discord_id: current_user_id,
            author_username: author_name,
            body: option(:note).to_s.strip
          )
          respond("📝 Note added to #{membership.mention}.")
        end
      end
    end
  end
end
