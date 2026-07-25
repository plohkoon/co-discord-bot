class AbsencesController < ApplicationController
  include GuildScoping

  # Cancel a call-out. Allowed for a Manage-Server user, a lead of the team, or
  # the raider who made it (a Discord-only member self-cancels from the guild
  # page). No roster refresh — call-outs aren't shown in the directory.
  def destroy
    absence = Absence.find(params[:id])
    unless can_cancel?(absence)
      return redirect_back fallback_location: guild_path(@guild), alert: "You can't cancel that call-out."
    end

    Absences::Cancel.call(absence, cancelled_by_discord_id: current_user.discord_id)
    redirect_back fallback_location: guild_path(@guild), notice: "Call-out cancelled."
  end

  private

  def can_cancel?(absence)
    can_manage? || officer_of?(absence.team) || absence.discord_user_id == current_user.discord_id
  end
end
