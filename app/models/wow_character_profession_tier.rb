# One expansion's worth of a profession — "Midnight Tailoring 30/100".
#
# Skill is tracked per expansion, so being capped in Classic Tailoring says
# nothing about whether someone can craft anything current. That's why tiers are
# rows rather than a single skill number on the profession.
class WowCharacterProfessionTier < ApplicationRecord
  belongs_to :wow_character_profession

  validates :tier_id, presence: true, uniqueness: { scope: :wow_character_profession_id }
  validates :name, presence: true

  scope :newest_first, -> { order(tier_id: :desc) }

  def maxed? = skill_points.present? && max_skill_points.present? && skill_points >= max_skill_points

  def progress
    return nil if skill_points.blank? || max_skill_points.to_i.zero?

    (skill_points.to_f / max_skill_points * 100).round
  end

  def summary = "#{name} #{skill_points}/#{max_skill_points}"
end
