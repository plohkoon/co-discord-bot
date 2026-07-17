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

  # Roster details (category + the free-form lines shown by /team roster).
  def update
    @team = @guild.teams.find(params[:id])
    attrs = params.require(:team).permit(:category_name, *Team::ROSTER_FIELDS)
    category_name = attrs.delete(:category_name)

    @team.assign_attributes(attrs)
    @team.team_category = TeamCategory.locate(category_name) # blank clears it

    if @team.save
      TeamRosterRefreshJob.perform_later(guild_id: @guild.id, team_id: @team.id)
      redirect_to guild_team_path(@guild, @team), notice: "Roster details updated."
    else
      redirect_to guild_team_path(@guild, @team), alert: @team.errors.full_messages.to_sentence
    end
  end
end
