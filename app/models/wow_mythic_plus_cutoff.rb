# One Mythic+ score percentile, for one season, region and faction.
#
# The M+ half of "what was this score actually worth". Blizzard publishes no
# cutoffs at all for Mythic+, so Raider.io's computed quantiles are the only
# source — unlike PvP, where Blizzard is first-party authoritative.
#
# Cutoffs drift all season as the ladder fills, so a changed value is a NEW row
# rather than an update: the movement is the point.
class WowMythicPlusCutoff < ApplicationRecord
  belongs_to :wow_season, foreign_key: :season_slug, primary_key: :slug,
                          inverse_of: false, optional: true

  # The percentile keys people actually quote, best first.
  PERCENTILES = %w[p999 p990 p900 p750 p600].freeze
  # Raider.io's named title tiers.
  TITLE_TIERS = %w[keystoneMyth keystoneLegend keystoneHero keystoneMaster
                   keystoneConqueror keystoneExplorer].freeze

  FACTIONS = %w[all horde alliance].freeze

  validates :season_slug, :region, :faction, :quantile_key, :min_score, :captured_at, presence: true

  scope :for_season, ->(slug) { where(season_slug: slug) }
  scope :for_region, ->(region) { where(region: region.to_s.downcase) }
  scope :percentiles, -> { where(quantile_key: PERCENTILES) }
  scope :title_tiers, -> { where(quantile_key: TITLE_TIERS) }
  scope :combined, -> { where(faction: "all") }
  # id breaks ties on captured_at — same-instant captures (a re-run, a coarse
  # clock) would otherwise resolve at random.
  scope :newest_first, -> { order(captured_at: :desc, id: :desc) }

  # The bar as it stands now.
  def self.latest_for(season_slug:, region:, quantile_key:, faction: "all")
    for_season(season_slug).for_region(region)
      .where(faction: faction, quantile_key: quantile_key)
      .newest_first.first
  end

  # "top 0.1%" / "top 25%" — derived from the quantile rather than the key, so a
  # new percentile Raider.io adds reads correctly without a lookup table.
  def label
    return quantile_key.underscore.humanize if quantile.blank?

    percent = ((1 - quantile.to_f) * 100).round(1)
    "top #{percent == percent.to_i ? percent.to_i : percent}%"
  end

  def score = min_score.to_f.round

  # How many players sit above this bar, of how many total.
  def population_summary
    return nil if population_count.blank? || total_population.blank?

    "#{ActiveSupport::NumberHelper.number_to_delimited(population_count)} of " \
      "#{ActiveSupport::NumberHelper.number_to_delimited(total_population)}"
  end
end
