class TeamsController < ApplicationController
  include GuildScoping

  def show
    @team = @guild.teams.find(params[:id])
    @questions = @team.application_questions.ordered
    @new_question = @team.application_questions.build(required: true)
    @applications = @team.team_applications.recent.limit(15)
  end
end
