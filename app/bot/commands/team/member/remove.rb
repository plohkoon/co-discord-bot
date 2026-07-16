module Commands
  module Team
    module Member
      class Remove < Commands::Base
        include Commands::MemberCommand
        description "Remove a member from the team (pulls the role + archives)"

        def member_scope(team) = team.team_memberships.where.not(status: TeamMembership.statuses[:archived])

        def call
          membership = resolve_membership or return

          begin
            Memberships::RoleManager.revoke(bot: event.bot, server: server, team: membership.team, discord_user_id: membership.discord_user_id)
          rescue Memberships::RoleError => e
            return respond("⚠️ #{e.message}")
          end

          Memberships::Archive.call(membership)
          respond("🚪 Removed #{membership.mention} from **#{membership.team.name}**.")
        end
      end
    end
  end
end
