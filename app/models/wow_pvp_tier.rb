# A PvP rating tier — Unranked, Combatant I/II, Challenger I/II, Rival I/II,
# Duelist, Elite — with the rating it starts at, per bracket.
#
# Turns the bare `tier: {id: 14}` on a rating row into "Elite (2275+)". Tiers
# shift between seasons, which is why they're synced rather than hardcoded.
class WowPvpTier < ApplicationRecord
  validates :blizzard_id, presence: true, uniqueness: true

  scope :by_rating, -> { order(min_rating: :asc) }

  def display_name = name.presence || "Tier #{blizzard_id}"

  # "Elite (2275+)"
  def label = min_rating.to_i.positive? ? "#{display_name} (#{min_rating}+)" : display_name
end
