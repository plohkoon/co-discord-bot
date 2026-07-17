class GuildsController < ApplicationController
  include GuildScoping
  before_action :require_guild_manager, only: :recheck

  def show
    @teams = @guild.teams.order(:name).to_a
    # One grouped query each instead of N per-team queries (tenant-scoped).
    @question_counts = ApplicationQuestion.group(:team_id).count
    @active_counts = TeamMembership.active.group(:team_id).count
    @pending_counts = TeamMembership.pending.group(:team_id).count
    # Teams the current user leads — they get to open those pages.
    @led_team_ids = current_user ? TeamOfficer.where(discord_user_id: current_user.discord_id).pluck(:team_id).to_set : Set.new
    # Permission health is a manager concern (and a REST call) — skip for members.
    @health = can_manage? ? Discord::GuildHealth.call(guild: @guild, teams: @teams) : nil
    # Curated roster lists, editable in the settings section (managers only).
    if can_manage?
      @team_categories = TeamCategory.ordered.to_a
      @team_types = TeamType.ordered.to_a
    end
  end

  # "Re-check" button on the health banner: bust the cache and re-render.
  def recheck
    Discord::GuildHealth.expire(@guild)
    redirect_to guild_path(@guild)
  end
end
