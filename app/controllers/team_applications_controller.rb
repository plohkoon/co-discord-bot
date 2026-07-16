class TeamApplicationsController < ApplicationController
  include GuildScoping

  def index
    @applications = TeamApplication.includes(:team).recent
    @applications = @applications.where(team_id: params[:team_id]) if params[:team_id].present?
    if TeamApplication.statuses.key?(params[:status])
      @applications = @applications.where(status: params[:status])
    end
  end

  def show
    @application = TeamApplication.includes(:team, :application_answers).find(params[:id])
  end
end
