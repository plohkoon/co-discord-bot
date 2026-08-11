# One profession on one character.
#
# Blizzard splits primaries from secondaries and the distinction is real:
# primaries are the two capped, chosen slots that a guild actually cares about,
# while secondaries (Cooking, Fishing, Archaeology) are free and near-universal.
class WowCharacterProfession < ApplicationRecord
  belongs_to :wow_character
  has_many :wow_character_profession_tiers, dependent: :destroy

  PRIMARY = "primary".freeze
  SECONDARY = "secondary".freeze

  # The professions that produce things other people want. Kept as a list so
  # "who can make me one of these" stays answerable without hardcoding it at
  # every call site.
  CRAFTING = %w[Alchemy Blacksmithing Enchanting Engineering Inscription
                Jewelcrafting Leatherworking Tailoring].freeze
  GATHERING = %w[Herbalism Mining Skinning].freeze

  validates :profession_id, presence: true, uniqueness: { scope: :wow_character_id }
  validates :name, :kind, presence: true

  scope :primary, -> { where(kind: PRIMARY) }
  scope :secondary, -> { where(kind: SECONDARY) }
  scope :crafting, -> { where(name: CRAFTING) }
  scope :named, ->(name) { where(name: name) }
  scope :by_name, -> { order(:name) }

  def primary? = kind == PRIMARY

  def crafting? = CRAFTING.include?(name)

  def gathering? = GATHERING.include?(name)

  # The most recent expansion's tier — the only one that says whether they can
  # craft anything current.
  #
  # Blizzard does not flag which tier is current, so this uses the highest tier
  # id. That is right for every character who has touched a modern expansion,
  # but the ids are NOT chronological in general: measured on a live character,
  # the legacy tiers were assigned in one descending batch (2501 Draenor is
  # *higher* than 2506 Classic), while each new expansion since has taken a
  # fresh higher id (2875 Khaz Algar, 2910 Midnight). So a character whose only
  # tiers are legacy ones can be misordered — for whom "current tier" is a
  # meaningless question anyway.
  def latest_tier = wow_character_profession_tiers.order(tier_id: :desc).first

  # "Tailoring 30/100" — the number a person would quote.
  def summary
    tier = latest_tier
    return name if tier.nil? || tier.skill_points.blank?

    "#{name} #{tier.skill_points}/#{tier.max_skill_points}"
  end
end
