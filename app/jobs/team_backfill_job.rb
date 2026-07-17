# Enqueued by /team create: pick up everyone already holding the team role as
# active members, then report the count back to the command's ephemeral thread.
class TeamBackfillJob < ApplicationJob
  queue_as :default

  retry_on Discord::BotApi::Error, wait: :polynomially_longer, attempts: 3
  discard_on Discord::BotApi::NotFound # bot kicked or guild gone — nothing to sweep

  def perform(guild_id:, team_id:, application_id: nil, interaction_token: nil)
    guild = Guild.find_by(id: guild_id) or return

    ActsAsTenant.with_tenant(guild) do
      team = Team.find_by(id: team_id) or return

      count = Memberships::Backfill.call(team: team)
      report(team, count, application_id, interaction_token)
    end

    # The new team (with its freshly seeded officers) joins the posted roster;
    # no-op if the roster was never posted.
    RosterRefreshJob.perform_later(guild_id: guild_id)
  end

  private

  # Best effort: the interaction token expires ~15 minutes after the ack, so a
  # backlogged job can miss the window — never fail the backfill over the report.
  def report(team, count, application_id, token)
    return unless count.positive? && application_id.present? && token.present?

    Discord::BotApi.new.interaction_followup(
      application_id: application_id,
      token: token,
      content: "👥 Picked up **#{count}** existing #{"holder".pluralize(count)} of the team role as active #{"member".pluralize(count)}."
    )
  rescue => e
    Rails.logger.warn("[jobs] backfill follow-up failed for team #{team.id}: #{e.class}: #{e.message}")
  end
end
