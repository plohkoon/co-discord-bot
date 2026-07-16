class MembershipNotesController < ApplicationController
  include GuildScoping
  before_action :set_membership

  def create
    note = @membership.membership_notes.build(
      body: params.dig(:membership_note, :body).to_s.strip,
      author_discord_id: current_user.discord_id,
      author_username: current_user.display_name
    )

    if note.body.present? && note.save
      redirect_to membership_path, notice: "Note added."
    else
      redirect_to membership_path, alert: "Note can't be blank."
    end
  end

  def destroy
    @membership.membership_notes.find(params[:id]).destroy
    redirect_to membership_path, notice: "Note removed."
  end

  private

  def set_membership
    @team = @guild.teams.find(params[:team_id])
    @membership = @team.team_memberships.find(params[:membership_id])
  end

  def membership_path
    guild_team_membership_path(@guild, @team, @membership)
  end
end
