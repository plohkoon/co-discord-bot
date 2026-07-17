# Accept/Reject from the web membership page — the same Applications::Decide
# path as the Discord buttons and the auto-reject sweep, so double-decisions
# lose the row-lock claim no matter where they come from.
class ApplicationDecisionsController < ApplicationController
  include GuildScoping
  before_action :set_application
  before_action :require_team_access

  def accept = decide(:accept)

  def reject = decide(:reject)

  private

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
