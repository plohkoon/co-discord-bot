namespace :co_bot do
  desc "Resolve pending applications stranded on non-pending memberships: system-reject on archived ones " \
       "(they block re-applying via the one-pending-per-user index), system-accept on active ones (a manual " \
       "role grant was the acceptance). Re-runs Archive/Activate, which also repaint review messages. " \
       "Safe to re-run anytime (idempotent)."
  task cleanup_stranded_applications: :environment do
    Guild.find_each do |guild|
      ActsAsTenant.with_tenant(guild) do
        stranded = TeamMembership.where.not(status: :pending)
                                 .joins(:team_applications).merge(TeamApplication.pending).distinct
        stranded.find_each do |membership|
          if membership.archived?
            Memberships::Archive.call(membership)
            verb = "rejected"
          else
            Memberships::Activate.call(team: membership.team, discord_user_id: membership.discord_user_id,
                                       username: membership.discord_username)
            verb = "accepted"
          end
          puts "#{guild.name} / #{membership.team.name}: #{verb} stranded application for " \
               "#{membership.discord_username} (#{membership.discord_user_id})"
        end
      end
    end
  end

  desc "Re-seed every team's members + officers mirrors from Discord (REST sweep), then reflow rosters. " \
       "Run once after a deploy that adds mirror tables; safe to re-run anytime (idempotent)."
  task backfill: :environment do
    Guild.installed.find_each do |guild|
      ActsAsTenant.with_tenant(guild) do
        Team.active.find_each do |team|
          count = Memberships::Backfill.call(team: team)
          puts "#{guild.name} / #{team.name}: #{count} member(s), #{team.team_officers.count} officer(s)"
        rescue Discord::BotApi::Error => e
          puts "#{guild.name} / #{team.name}: FAILED (#{e.class}: #{e.message})"
        end
      end

      RosterRefreshJob.perform_now(guild_id: guild.id)
      puts "#{guild.name}: roster reflowed"
    end
  end
end
