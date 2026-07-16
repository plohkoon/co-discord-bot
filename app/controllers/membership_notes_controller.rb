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
      redirect_back_to_review notice: "Note added."
    else
      redirect_back_to_review alert: "Note can't be blank."
    end
  end

  def destroy
    @membership.membership_notes.find(params[:id]).destroy
    redirect_back_to_review notice: "Note removed."
  end

  private

  def set_membership
    @membership = TeamMembership.find(params[:membership_id])
  end

  def redirect_back_to_review(**flash_opts)
    redirect_back fallback_location: guild_team_path(@guild, @membership.team), **flash_opts
  end
end
