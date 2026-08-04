# One character's progression in one raid tier ("1/9 M").
#
# Like WowCharacterSeason, this is a table because old tiers stop moving: a
# closed tier's kill counts are history, and keeping them per-row means an
# applicant's full raiding record survives instead of being overwritten by
# whatever they're working on now.
class WowCharacterRaid < ApplicationRecord
  belongs_to :wow_character
  belongs_to :wow_raid, foreign_key: :raid_slug, primary_key: :slug,
                        inverse_of: :wow_character_raids, optional: true

  validates :raid_slug, presence: true, uniqueness: { scope: :wow_character_id }

  DIFFICULTY_RANK = { "M" => 300, "H" => 200, "N" => 100 }.freeze

  # Anything actually killed. Raider.io returns a row with an empty summary for
  # raids the character has never set foot in.
  scope :attempted, -> { where.not(summary: [ nil, "" ]) }

  # Ordering is by #rank, which is derived rather than stored (difficulty beats
  # kill count, and the difficulty is itself derived from three columns). A
  # character has a handful of raid rows, so sorting them in Ruby is cheaper
  # than carrying a denormalised column that could drift.
  def self.best_first = order(:raid_slug).to_a.sort_by { |r| -r.rank }

  def raid_name = wow_raid&.display_name || raid_slug

  def attempted? = summary.present?

  def highest_difficulty
    return "M" if mythic_bosses_killed.to_i.positive?
    return "H" if heroic_bosses_killed.to_i.positive?
    return "N" if normal_bosses_killed.to_i.positive?

    nil
  end

  def killed_at_highest
    case highest_difficulty
    when "M" then mythic_bosses_killed.to_i
    when "H" then heroic_bosses_killed.to_i
    when "N" then normal_bosses_killed.to_i
    else 0
    end
  end

  # Difficulty dominates, kills break ties — "1/9 M" outranks "9/9 H".
  def rank
    (DIFFICULTY_RANK[highest_difficulty] || 0) + killed_at_highest
  end
end
