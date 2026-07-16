module Commands
  module Team
    module Member
      class Accept < Commands::Base
        include Commands::MemberCommand
        description "Accept a member's pending application"

        def member_scope(team) = team.team_memberships.pending

        def call
          membership = resolve_membership or return
          application = membership.open_application
          return respond("#{membership.mention} has no pending application.") unless application

          result = Applications::Decide.call(
            application: application,
            decision: :accept,
            decided_by_discord_id: current_user_id,
            role_granter: ->(_app) { Memberships::RoleManager.grant(bot: event.bot, server: server, team: membership.team, discord_user_id: membership.discord_user_id) }
          )
          respond(result_message(result, membership, verb: "accepted"))
        end
      end
    end
  end
end
