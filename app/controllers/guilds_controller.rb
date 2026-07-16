class GuildsController < ApplicationController
  include GuildScoping

  def show
    @teams = @guild.teams.order(:name).to_a
    # One grouped query each instead of N per-team queries (tenant-scoped).
    @question_counts = ApplicationQuestion.group(:team_id).count
    @active_counts = TeamMembership.active.group(:team_id).count
    @pending_counts = TeamMembership.pending.group(:team_id).count
  end
end
