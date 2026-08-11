# A career-defining achievement, with the date it was earned.
#
# Matched by **name pattern rather than id list**, deliberately. Blizzard mints
# new "Ahead of the Curve: <boss>" and "<Season> Gladiator" achievements every
# tier, so an id list would silently stop recognising the newest — and the
# newest is exactly the one a recruiter asks about. The four evergreen PvP
# titles are pinned by id because their names ("Duelist", "Rival") are too
# generic to match safely.
class WowCharacterAchievement < ApplicationRecord
  belongs_to :wow_character

  # The evergreen PvP titles. Fixed ids because matching /Duelist/ by name would
  # also catch "Darkmoon Duelist" (verified: a real, unrelated achievement).
  PVP_TITLE_IDS = { 2091 => "Gladiator", 2092 => "Duelist",
                    2093 => "Rival", 2090 => "Challenger" }.freeze

  # category => matcher. Order matters: the first match wins, so the specific
  # seasonal Gladiator mounts are tested before the generic title ids.
  CATEGORIES = {
    # "Cutting Edge: Dimensius, the All-Devouring" — killed the final boss on
    # mythic before the tier ended. The strongest PvE credential there is.
    "cutting_edge" => ->(id, name) { name.start_with?("Cutting Edge:") },
    # "Ahead of the Curve: N'Zoth the Corruptor" — heroic before the tier ended.
    "aotc" => ->(id, name) { name.start_with?("Ahead of the Curve:") },
    # Seasonal Gladiator mounts: "Sinful Gladiator's Soul Eater" etc. These pin
    # a specific season, which the evergreen title does not.
    "gladiator" => ->(id, name) { name.match?(/\bGladiator('s)?\b/) },
    "pvp_title" => ->(id, _name) { PVP_TITLE_IDS.key?(id) },
    # The M+ seasonal titles: "Keystone Master", "Keystone Hero", "Keystone
    # Legend". The colon exclusion is load-bearing — Blizzard also mints a
    # per-dungeon achievement for every dungeon ("Keystone Hero: Seat of the
    # Triumvirate"), and one live character had 39 of them against 3 real
    # titles. Those are a completion log, not a credential.
    "keystone" => ->(id, name) { name.start_with?("Keystone ") && !name.include?(":") }
  }.freeze

  validates :blizzard_id, presence: true, uniqueness: { scope: :wow_character_id }
  validates :name, :category, presence: true

  scope :newest_first, -> { order(Arel.sql("completed_at IS NULL"), completed_at: :desc) }
  scope :in_category, ->(category) { where(category: category) }
  scope :raid_credentials, -> { where(category: %w[cutting_edge aotc]) }
  scope :pvp_credentials, -> { where(category: %w[gladiator pvp_title]) }

  # Which category an achievement belongs to, or nil if it isn't career-defining.
  def self.categorize(id, name)
    CATEGORIES.each { |category, matcher| return category if matcher.call(id.to_i, name.to_s) }
    nil
  end

  def earned_on = completed_at&.to_date

  # "Cutting Edge: Dimensius, the All-Devouring (Apr 2024)" — the date is the
  # claim, so it travels with the name.
  def summary
    return name if completed_at.blank?

    "#{name} (#{completed_at.strftime("%b %Y")})"
  end
end
