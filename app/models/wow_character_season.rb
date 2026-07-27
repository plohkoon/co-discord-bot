# One character's Mythic+ score in one season.
#
# The reason this is a table and not a column: **a finished season's score never
# changes**. Once Raider.io has told us what someone scored in season-tww-2,
# that row is correct forever — so it is fetched exactly once and then only
# read. Only the live season is ever re-fetched.
#
# That's also what makes score *history* cheap, which is the recruiting signal
# worth having: "2900+ for three straight seasons" says far more than one
# current number.
class WowCharacterSeason < ApplicationRecord
  belongs_to :wow_character
  # By slug, not id — Raider.io may report a season our static-data sync hasn't
  # seen yet, and an unlabelled score beats a dropped one.
  belongs_to :wow_season, foreign_key: :season_slug, primary_key: :slug,
                          inverse_of: :wow_character_seasons, optional: true

  validates :season_slug, presence: true, uniqueness: { scope: :wow_character_id }

  scope :newest_first, -> { joins(:wow_season).merge(WowSeason.newest_first) }
  scope :scored, -> { where(score_all: 0.1..) }

  ROLES = %w[all tank healer dps].freeze

  def score_for(role) = self[:"score_#{role}"]

  # Zero is "didn't run keys", not a score — same rule as WowCharacter.
  def scored? = score_all.present? && score_all.positive?

  def score = scored? ? score_all.round : nil

  # The role this character actually played that season: their highest-scoring
  # one. Raider.io gives a per-role split but doesn't name a primary.
  def primary_role
    best = %w[tank healer dps].max_by { |r| score_for(r) || 0 }
    best if (score_for(best) || 0).positive?
  end

  def season_name = wow_season&.display_name || season_slug

  # A season that has ended can never change again, so it never needs re-fetching.
  def final?(now = Time.current) = wow_season&.ended?(now) || false
end
