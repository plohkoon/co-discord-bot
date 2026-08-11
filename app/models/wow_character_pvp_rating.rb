# One character's rating in one bracket in one season.
#
# Solo Shuffle and Blitz are rated per SPECIALISATION, so a single character
# legitimately holds several rows at once — `bracket` is the raw Blizzard slug
# ("3v3", "shuffle-mage-frost") with `bracket_type` and `spec_slug` parsed out
# so neither has to be re-derived at read time.
#
# These rows are the only record that will ever exist of a past season: Blizzard
# answers for the current season only.
class WowCharacterPvpRating < ApplicationRecord
  belongs_to :wow_character

  # 2v2/3v3/rbg carry one rating; shuffle and blitz are per-spec.
  TEAM_BRACKETS = %w[2v2 3v3 rbg].freeze
  PER_SPEC_BRACKETS = %w[shuffle blitz].freeze

  validates :bracket, presence: true,
                      uniqueness: { scope: %i[wow_character_id season_id] }

  scope :for_season, ->(id) { where(season_id: id) }
  scope :rated, -> { where(rating: 1..) }
  scope :best_first, -> { order(rating: :desc) }
  scope :team_brackets, -> { where(bracket_type: TEAM_BRACKETS) }

  # "3v3" / "Solo Shuffle (Frost Mage)" — what a person would call it.
  def display_bracket
    return bracket_type.upcase if bracket_type == "rbg"
    return bracket_type if TEAM_BRACKETS.include?(bracket_type)

    label = bracket_type == "shuffle" ? "Solo Shuffle" : "Blitz"
    spec_slug.present? ? "#{label} (#{spec_slug.tr("-", " ").titleize})" : label
  end

  def tier = tier_id && WowPvpTier.find_by(blizzard_id: tier_id)

  def tier_name = tier&.display_name

  def win_rate
    return nil unless played.to_i.positive?

    (won.to_f / played * 100).round
  end

  def played_this_week? = weekly_played.to_i.positive?

  # Split a Blizzard bracket slug into its type and spec.
  #   "3v3"                -> ["3v3", nil]
  #   "shuffle-mage-frost" -> ["shuffle", "mage-frost"]
  def self.parse_bracket(slug)
    type, rest = slug.to_s.split("-", 2)
    return [ slug.to_s, nil ] unless PER_SPEC_BRACKETS.include?(type)

    [ type, rest.presence ]
  end
end
