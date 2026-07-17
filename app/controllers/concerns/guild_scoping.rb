# For dashboard controllers scoped to one guild. Authorizes that the current
# user can at least view the guild (they're a member, hold Manage Server, or
# lead a team in it), then runs the action inside the guild tenant so every
# query is auto-scoped (acts_as_tenant).
#
# Finer gates for controllers to opt into per action:
#   before_action :require_guild_manager  — Manage Server only
#   before_action :require_team_access    — Manage Server or a lead of @team
module GuildScoping
  extend ActiveSupport::Concern

  included do
    before_action :set_guild
    around_action :scope_to_guild
    helper_method :can_manage?, :officer_of?
  end

  private

  def set_guild
    id = params[:guild_id] || params[:id]

    unless can_view_guild?(id)
      redirect_to(root_path, alert: "You don't have access to that server.")
      return
    end

    @guild = Guild.find_by(id: id)
    if @guild.nil?
      redirect_to(root_path, alert: "That server isn't set up yet.")
    elsif @guild.removed?
      @guild = nil
      redirect_to(root_path, alert: "co-bot was removed from that server. Re-invite it to manage it again.")
    end
  end

  def scope_to_guild(&block)
    return unless @guild # a redirect already happened in set_guild

    ActsAsTenant.with_tenant(@guild, &block)
  end

  def can_manage? = can_manage_guild?(@guild&.id)

  # Team-lead check against the team_officers mirror (kept in sync by
  # RoleSync on every member_update, so it's near-live).
  def officer_of?(team)
    return false unless current_user

    TeamOfficer.exists?(team_id: team.id, discord_user_id: current_user.discord_id)
  end

  def require_guild_manager
    return if can_manage?

    redirect_to guild_path(@guild), alert: "You need Manage Server to do that."
  end

  def require_team_access
    return if can_manage? || officer_of?(@team)

    redirect_to guild_path(@guild), alert: "Only this team's leads can open that."
  end
end
