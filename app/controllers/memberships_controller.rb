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
  # A lead sets which character this member is active as on their team. Scoped
  # to characters the MEMBER owns — a lead can correct a typo or a swap, not
  # attribute someone else's character to them.
  def set_character
    membership = @team.team_memberships.find(params[:id])
    character = membership.user&.wow_characters&.find_by(id: params[:wow_character_id])

    membership.update!(wow_character: character)
    redirect_to guild_team_membership_path(@guild, @team, membership),
                notice: character ? "Active character set to #{character.full_name}." : "Active character cleared."
  end

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
