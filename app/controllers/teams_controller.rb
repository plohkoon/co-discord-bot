class TeamsController < ApplicationController
  include GuildScoping

  def show
    @team = @guild.teams.find(params[:id])
    @questions = @team.application_questions.ordered
    @new_question = @team.application_questions.build(required: true)

    memberships = @team.team_memberships.order(updated_at: :desc).to_a
    @members_by_status = memberships.group_by(&:status)
    @counts = %w[active pending archived].index_with { |status| @members_by_status[status]&.size || 0 }
    @app_counts = TeamApplication.where(team_membership_id: memberships.map(&:id)).group(:team_membership_id).count
  end
end
