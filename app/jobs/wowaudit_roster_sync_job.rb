# Refresh every connected team's wowaudit roster.
#
# Rosters move at human speed — someone joins the team, someone is benched — so
# daily is ample. Per-team keys mean one team's revoked key can't stop the rest,
# hence the rescue around each.
#
# No-op for teams without a key, which is most of them.
class WowauditRosterSyncJob < ApplicationJob
  queue_as :default

  def perform(team_id: nil)
    teams(team_id).each do |guild, team|
      ActsAsTenant.with_tenant(guild) do
        result = WowAudit::SyncRoster.call(team)
        if result.ok?
          Rails.logger.info("[wowaudit] #{team.name}: #{result.synced} on roster, " \
                            "#{result.matched} matched, #{result.removed} removed")
        else
          Rails.logger.warn("[wowaudit] #{team.name}: #{result.error}")
        end
      end
    rescue => e
      # One team's broken integration must not stop the others.
      Rails.logger.error("[wowaudit] sync failed for team #{team.id}: #{e.class}: #{e.message}")
    end
  end

  private

  # acts_as_tenant scopes Team, so the guild has to be established before the
  # teams can be read — walk guilds rather than querying Team globally.
  def teams(team_id)
    Guild.installed.flat_map do |guild|
      ActsAsTenant.with_tenant(guild) do
        scope = Team.active.with_wowaudit
        scope = scope.where(id: team_id) if team_id
        scope.to_a.map { |team| [ guild, team ] }
      end
    end
  end
end
