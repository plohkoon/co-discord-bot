# DMs an applicant the team's acknowledgement after they apply (kind: "apply").
# The "absence" kind is the same primitive wired ahead of the attendance
# feature — nothing triggers it yet. Best-effort: a closed DM is swallowed in
# Notifications::DirectMessage (Forbidden/NotFound), so it never retries; only a
# transient BotApi::Error retries.
class ConfirmationDmJob < ApplicationJob
  queue_as :default

  retry_on Discord::BotApi::Error, wait: :polynomially_longer, attempts: 3

  def perform(guild_id:, team_id:, discord_user_id:, kind:)
    guild = Guild.find_by(id: guild_id) or return

    ActsAsTenant.with_tenant(guild) do
      team = Team.find_by(id: team_id) or next

      content = template_for(team, kind, "<@#{discord_user_id}>") or next
      Notifications::DirectMessage.call(user_id: discord_user_id, content: content)
    end
  end

  private

  def template_for(team, kind, user_mention)
    case kind.to_s
    when "apply"   then team.resolved_apply_response(user_mention:)
    when "absence" then team.resolved_absence_response(user_mention:)
    end
  end
end
