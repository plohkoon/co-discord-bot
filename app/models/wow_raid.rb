# A raid tier, from Raider.io's static data. Shared reference data, kept for the
# display name and boss count — raid_progression is keyed by slug ("tier-mn-1"),
# which is not something to show a person.
class WowRaid < ApplicationRecord
  has_many :wow_character_raids, foreign_key: :raid_slug, primary_key: :slug,
                                 inverse_of: :wow_raid, dependent: nil
  has_many :wow_encounters, foreign_key: :raid_slug, primary_key: :slug,
                            inverse_of: :wow_raid, dependent: nil

  validates :slug, presence: true, uniqueness: true

  scope :newest_first, -> { order(expansion_id: :desc, id: :desc) }

  def display_name = name.presence || slug

  # The Warcraft Logs zone(s) covering this tier, derived from bosses the two
  # services agree on (see WowEncounter). Usually one; more when Warcraft Logs
  # splits a tier Raider.io groups. Empty until Warcraft Logs is configured.
  def warcraft_logs_zone_ids
    wow_encounters.where.not(wcl_zone_id: nil).distinct.pluck(:wcl_zone_id)
  end

  def warcraft_logs_zones
    ids = warcraft_logs_zone_ids
    ids.any? ? WarcraftLogsZone.where(wcl_id: ids) : WarcraftLogsZone.none
  end
end
