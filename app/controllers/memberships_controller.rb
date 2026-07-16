class MembershipsController < ApplicationController
  include GuildScoping
  before_action :set_team

  def show
    @membership = @team.team_memberships.find(params[:id])
    @applications = @membership.team_applications.includes(:application_answers).recent
    @notes = @membership.membership_notes
  end

  private

  def set_team
    @team = @guild.teams.find(params[:team_id])
  end
end
