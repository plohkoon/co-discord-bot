# One character's parse percentiles in one raid tier at one difficulty.
#
# The recruiting number. Blizzard says what gear someone has and Raider.io says
# what they've killed; this says how well they actually played while doing it.
#
# A row for a frozen zone is history and is never re-fetched (see
# WarcraftLogsZone).
class WarcraftLogsRanking < ApplicationRecord
  belongs_to :wow_character
  # By Warcraft Logs' own zone id rather than an FK, for the same reason the
  # Raider.io satellites join by slug: a ranking must survive arriving before
  # the zone sync has seen the tier.
  belongs_to :warcraft_logs_zone, foreign_key: :wcl_zone_id, primary_key: :wcl_id,
                                  inverse_of: :warcraft_logs_rankings, optional: true

  validates :wcl_zone_id, presence: true
  validates :difficulty, presence: true,
                         uniqueness: { scope: %i[wow_character_id wcl_zone_id] }

  scope :mythic, -> { where(difficulty: WarcraftLogsZone::MYTHIC) }
  scope :with_kills, -> { where(total_kills: 1..) }
  scope :newest_first, -> { joins(:warcraft_logs_zone).merge(WarcraftLogsZone.newest_first) }

  def zone_name = warcraft_logs_zone&.display_name || "Zone #{wcl_zone_id}"

  def difficulty_name = WarcraftLogsZone.difficulty_name(difficulty)

  def logged? = total_kills.to_i.positive?

  # Percentiles are conventionally quoted whole.
  def best = best_performance_average&.round

  def median = median_performance_average&.round

  # What a recruiter reads first: the typical night, not the lucky pull. Falls
  # back to best when there aren't enough kills for a median to mean anything.
  def headline = median || best

  # A 99 off one kill is not the claim a 99 off thirty is, so the kill count
  # travels with the number wherever it's shown.
  def summary
    return nil unless logged? && headline

    "#{headline} #{difficulty_name} (#{total_kills} #{"kill".pluralize(total_kills)})"
  end

  # A frozen tier's parses are history and never need re-fetching.
  def final? = warcraft_logs_zone&.closed? || false
end
