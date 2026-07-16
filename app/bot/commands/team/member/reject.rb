module Commands
  module Team
    module Member
      class Reject < Commands::Base
        include Commands::MemberCommand
        description "Reject a member's pending application"

        def member_scope(team) = team.team_memberships.pending

        def call
          membership = resolve_membership or return
          application = membership.open_application
          return respond("#{membership.mention} has no pending application.") unless application

          result = Applications::Decide.call(application: application, decision: :reject, decided_by_discord_id: current_user_id)
          respond(result_message(result, membership, verb: "rejected"))
        end
      end
    end
  end
end
