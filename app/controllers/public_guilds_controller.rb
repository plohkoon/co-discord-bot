# The shareable "apply to this guild" page: /apply/:guild_id. Everyone signed
# in sees the guild's active teams — recruiting ones with an Apply link, closed
# ones with their closed notice, matching the Discord roster. Visitors not in
# the Discord server yet get a prominent join banner on top (invite link when
# the guild has one configured): they can apply now, but must join to actually
# be added to a team.
class PublicGuildsController < PublicBaseController
  def show
    # Same grouping as the Discord roster directory: categories in position
    # order, teams by position within one, uncategorized last.
    teams = Team.active.includes(:team_category, :team_type, :team_officers).to_a
    @grouped_teams = CoBot::RosterMessage.grouped(teams)
  end
end
