# Manage Server CRUD for the guild's team-type vocabulary (the "type" roster
# line). Teams pick from this list — types are never created on the fly from a
# team form or command. Renames, reorders, and removals show up in any posted
# roster via RosterRefreshJob.
class TeamTypesController < ApplicationController
  include GuildScoping
  before_action :require_guild_manager

  def create
    team_type = TeamType.new(team_type_params)
    if team_type.save
      redirect_to guild_path(@guild), notice: "Team type added."
    else
      redirect_to guild_path(@guild), alert: team_type.errors.full_messages.to_sentence
    end
  end

  def update
    team_type = TeamType.find(params[:id])
    if team_type.update(team_type_params)
      RosterRefreshJob.perform_later(guild_id: @guild.id)
      redirect_to guild_path(@guild), notice: "Team type updated."
    else
      redirect_to guild_path(@guild), alert: team_type.errors.full_messages.to_sentence
    end
  end

  def destroy
    TeamType.find(params[:id]).destroy # its teams stay, just without a type line
    RosterRefreshJob.perform_later(guild_id: @guild.id)
    redirect_to guild_path(@guild), notice: "Team type removed."
  end

  private

  def team_type_params
    params.require(:team_type).permit(:name, :position)
  end
end
