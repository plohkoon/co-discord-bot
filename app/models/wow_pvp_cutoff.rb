# The rating needed for a season's title, per bracket and specialisation.
#
# The reason PvP ratings are worth storing at all. Measured in season 41: the
# same Shuffle title needed 2205 on one spec and 2998 on another — so a rating
# quoted without its contemporaneous cutoff can't be interpreted later.
#
# Cutoffs drift all season as the ladder fills, so a changed value is a NEW row
# (the unique index is on the value itself). That gives a step history of how
# the bar moved, rather than only its final position.
class WowPvpCutoff < ApplicationRecord
  belongs_to :wow_pvp_season, foreign_key: :season_id, primary_key: :blizzard_id,
                              inverse_of: :wow_pvp_cutoffs, optional: true

  validates :season_id, :bracket_type, :rating_cutoff, :captured_at, presence: true

  scope :for_season, ->(id) { where(season_id: id) }
  # id breaks ties on captured_at. Two cutoffs recorded in the same instant is
  # not hypothetical — a backfill, a re-run, or simply a coarse clock will do
  # it — and without the tiebreak "the current bar" resolves at random.
  scope :newest_first, -> { order(captured_at: :desc, id: :desc) }

  # The bar as it stands now for one bracket/spec.
  def self.latest_for(season_id:, bracket_type:, specialization_id: nil)
    for_season(season_id)
      .where(bracket_type: bracket_type, specialization_id: specialization_id)
      .newest_first.first
  end
end
