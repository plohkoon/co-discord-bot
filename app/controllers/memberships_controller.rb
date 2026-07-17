class MembershipsController < ApplicationController
  include GuildScoping
  before_action :set_team
  before_action :require_team_access
  before_action :set_membership

  def show
    @applications = @membership.team_applications.includes(:application_answers).recent
    @notes = @membership.membership_notes
  end

  # Pull the team role and archive — the web mirror of /team member remove.
  def remove
    if @membership.archived?
      return redirect_to guild_team_membership_path(@guild, @team, @membership),
                         alert: "Already removed."
    end

    begin
      Memberships::RestRoleManager.revoke(team: @team, discord_user_id: @membership.discord_user_id)
    rescue Memberships::RoleError => e
      return redirect_to guild_team_membership_path(@guild, @team, @membership), alert: "⚠️ #{e.message}"
    end

    Memberships::Archive.call(@membership)
    redirect_to guild_team_path(@guild, @team),
                notice: "Removed #{@membership.discord_username.presence || "the member"} from #{@team.name}."
  end

  private

  def set_team
    @team = @guild.teams.find(params[:team_id])
  end

  def set_membership
    @membership = @team.team_memberships.find(params[:id])
  end
end
