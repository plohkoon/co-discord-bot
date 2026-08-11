# A Warcraft Logs raid zone (a tier). Shared reference data.
#
# `closed` is the field this table exists for: Warcraft Logs calls it `frozen`
# and sets it when a tier closes, at which point its rankings can never change
# again. That's what lets WarcraftLogs::RefreshCharacter fetch a tier's parses
# once and never ask twice. (Renamed on the way in — Active Record won't allow a
# `frozen` attribute, since it would shadow Object#frozen?.)
#
# Deliberately NOT reconciled with `wow_raids` (Raider.io's view of the same
# tiers): the two services slug and split tiers differently, and a guessed
# mapping would quietly corrupt both sides.
class WarcraftLogsZone < ApplicationRecord
  has_many :warcraft_logs_rankings, foreign_key: :wcl_zone_id, primary_key: :wcl_id,
                                    inverse_of: :warcraft_logs_zone, dependent: nil
  has_many :wow_encounters, foreign_key: :wcl_zone_id, primary_key: :wcl_id,
                            inverse_of: :warcraft_logs_zone, dependent: nil

  validates :wcl_id, presence: true, uniqueness: true

  RAID = "raid".freeze
  MYTHIC_PLUS = "mythic_plus".freeze

  # Warcraft Logs lists raid tiers and Mythic+ seasons together. Their
  # difficulty ids are what tell them apart: raids offer 3/4/5, M+ offers 10.
  MYTHIC_PLUS_DIFFICULTY = 10

  def self.kind_from_difficulties(ids)
    Array(ids).map(&:to_i).include?(MYTHIC_PLUS_DIFFICULTY) ? MYTHIC_PLUS : RAID
  end

  scope :raids, -> { where(kind: RAID) }
  scope :mythic_plus, -> { where(kind: MYTHIC_PLUS) }
  scope :live, -> { where(closed: false) }
  scope :closed, -> { where(closed: true) }
  scope :newest_first, -> { order(expansion_id: :desc, wcl_id: :desc) }

  # Raid difficulties, by Blizzard's ids. Mythic is the one recruiters read.
  MYTHIC = 5
  HEROIC = 4
  NORMAL = 3
  DIFFICULTY_NAMES = { MYTHIC => "Mythic", HEROIC => "Heroic", NORMAL => "Normal",
                       MYTHIC_PLUS_DIFFICULTY => "Mythic+" }.freeze

  def self.difficulty_name(id) = DIFFICULTY_NAMES[id] || "Difficulty #{id}"

  def raid? = kind == RAID

  def display_name = name.presence || "Zone #{wcl_id}"

  # The Raider.io tier(s) this zone covers, derived from shared bosses.
  def wow_raid_slugs = wow_encounters.where.not(raid_slug: nil).distinct.pluck(:raid_slug)

  def wow_raids
    slugs = wow_raid_slugs
    slugs.any? ? WowRaid.where(slug: slugs) : WowRaid.none
  end
end
