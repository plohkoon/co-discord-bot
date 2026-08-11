# A Blizzard PvP season. Shared reference data.
#
# Unlike Raider.io's M+ seasons, a *past* PvP season is not backfillable: the
# character endpoint only ever answers for the current season. So this table
# says which season a stored rating belongs to, and nothing more can be
# recovered about the others after the fact.
class WowPvpSeason < ApplicationRecord
  has_many :wow_pvp_cutoffs, foreign_key: :season_id, primary_key: :blizzard_id,
                             inverse_of: :wow_pvp_season, dependent: nil

  validates :blizzard_id, presence: true, uniqueness: true

  scope :newest_first, -> { order(blizzard_id: :desc) }

  def self.current = find_by(current: true) || newest_first.first

  # "Midnight Season 1" out of "Player vs. Player (Midnight Season 1)".
  def display_name
    name.to_s[/\(([^)]+)\)/, 1].presence || name.presence || "Season #{blizzard_id}"
  end
end
