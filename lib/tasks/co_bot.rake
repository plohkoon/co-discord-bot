namespace :co_bot do
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
