# One posted team directory: the channel it lives in, the messages it spans
# (in display order) and, optionally, the categories it is limited to — so a
# guild can keep e.g. its retail teams in one channel and another set in
# another. Created or replaced by /guild roster, kept current by
# RosterRefreshJob.
class RosterPost < ApplicationRecord
  include GuildScoped

  serialize :category_ids, coder: JSON
  serialize :message_ids, coder: JSON, type: Array

  validates :channel_id, presence: true
  validates_uniqueness_to_tenant :channel_id

  # Whether any posted roster shows one of these teams — gates refreshes that
  # only matter when the team is on display.
  def self.showing?(teams)
    posts = all.to_a
    Array(teams).any? { |team| posts.any? { |post| post.covers?(team) } }
  end

  def filtered? = !category_ids.nil?

  # Unfiltered rosters show every team, uncategorized ones included; filtered
  # ones only teams in their categories.
  def covers?(team) = !filtered? || category_ids.include?(team.team_category_id)

  def teams_from(teams) = teams.select { |team| covers?(team) }
end
