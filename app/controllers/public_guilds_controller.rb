# The shareable "apply to this guild" page: /apply/:guild_id. Members see the
# guild's active teams — recruiting ones with an Apply link, closed ones with
# their closed notice, matching the Discord roster — non-members get a join
# card (invite link when the guild has one configured).
class PublicGuildsController < PublicBaseController
  def show
    return unless guild_member?

    # Same grouping as the Discord roster directory: categories in position
    # order, teams by position within one, uncategorized last.
    teams = Team.active.includes(:team_category, :team_type, :team_officers).to_a
    @grouped_teams = CoBot::RosterMessage.grouped(teams)
  end
end
