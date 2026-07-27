# One observed WoW Token price in one region.
#
# Blizzard only serves the current value, so this table is the only place the
# history exists — which is the whole point, since the movement is the
# interesting part, not the number.
class WowTokenPrice < ApplicationRecord
  COPPER_PER_GOLD = 10_000

  validates :region, :price, :recorded_at, presence: true
  validates :recorded_at, uniqueness: { scope: :region }

  scope :for_region, ->(region) { where(region: region.to_s.downcase) }
  scope :newest_first, -> { order(recorded_at: :desc) }

  def self.latest(region = BattleNet::Client::DEFAULT_REGION)
    for_region(region).newest_first.first
  end

  # The most recent price at or before `time` — used to answer "what was it a
  # week ago" without assuming a fixed polling cadence.
  def self.at_or_before(time, region: BattleNet::Client::DEFAULT_REGION)
    for_region(region).where(recorded_at: ..time).newest_first.first
  end

  def gold = price / COPPER_PER_GOLD

  # "278,942g" — the form the game shows.
  def to_gold_s = "#{ActiveSupport::NumberHelper.number_to_delimited(gold)}g"

  # Change against the most recent reading at least `since` ago. Returns nil
  # when there's no history that far back yet, which is the normal state for
  # the first week after this ships.
  def change_since(since)
    previous = self.class.at_or_before(recorded_at - since, region: region)
    return nil if previous.nil? || previous.id == id

    gold - previous.gold
  end

  # "+12,430g" / "-3,100g", signed so direction reads at a glance.
  def self.format_change(delta)
    return nil if delta.nil?

    sign = delta.negative? ? "−" : "+"
    "#{sign}#{ActiveSupport::NumberHelper.number_to_delimited(delta.abs)}g"
  end
end
