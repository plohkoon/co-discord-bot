# Accept/Reject from the web membership page — the same Applications::Decide
# path as the Discord buttons and the auto-reject sweep, so double-decisions
# lose the row-lock claim no matter where they come from.
class ApplicationDecisionsController < ApplicationController
  include GuildScoping
  before_action :set_application
  before_action :require_team_access

  def accept = decide(:accept)

  def reject = decide(:reject)

  # Park / un-park — the same Applications::Pause path as the review-message
  # buttons. Resuming restarts the reminder clock from scratch.
  def pause
    park Applications::Pause.pause(application: @application, actor_discord_id: current_user.discord_id),
         notice: "Application paused — reminders and the 7-day auto-reject are off until you resume it."
  end

  def resume
    park Applications::Pause.resume(application: @application),
         notice: "Application resumed — the 7-day review clock starts again now."
  end

  private

  def park(result, notice:)
    if result.status == :already_decided
      return redirect_to membership_path, alert: "This application was already handled."
    end

    # Repaint the Discord review message so both surfaces agree, even when the
    # button press lost a race (:already_paused / :not_paused).
    Applications::RefreshReviewMessage.call(@application.reload)
    redirect_to membership_path, notice: result.status == :ok ? notice : "Nothing to change — the application was already in that state."
  end

  def set_application
    @team = @guild.teams.find(params[:team_id])
    @membership = @team.team_memberships.find(params[:membership_id])
    @application = @membership.team_applications.find(params[:id])
  end

  def decide(decision)
    result = Applications::Decide.call(
      application: @application,
      decision: decision,
      decided_by_discord_id: current_user.discord_id,
      role_granter: ->(app) { Memberships::RestRoleManager.grant(team: @team, discord_user_id: app.discord_user_id) }
    )

    case result.status
    when :already_decided
      redirect_to membership_path, alert: "This application was already handled."
    when :error
      redirect_to membership_path, alert: "⚠️ #{result.error}"
    else
      # Repaint the Discord review message like a button decision would.
      Applications::RefreshReviewMessage.call(@application.reload)
      redirect_to membership_path, notice: "Application #{decision == :accept ? "accepted" : "rejected"}."
    end
  end

  def membership_path = guild_team_membership_path(@guild, @team, @membership)
end
