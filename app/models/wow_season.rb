# A Mythic+ season, from Raider.io's static data. Shared reference data — a few
# dozen rows for the whole app, not per character.
#
# Its job is to answer two questions the refresh loop depends on: which seasons
# should a character have a score row for, and which of those can never change
# again (see WowCharacterSeason).
class WowSeason < ApplicationRecord
  has_many :wow_character_seasons, foreign_key: :season_slug, primary_key: :slug,
                                   inverse_of: :wow_season, dependent: nil

  validates :slug, presence: true, uniqueness: true

  # Raider.io mints slugs for events and re-cuts alongside the real ladder:
  #   season-tww-3-break-the-meta, season-df-2-post-1017, season-df-4-cutoffs,
  #   season-tww-3-legion-remix, season-df-3-meta-vs-meta
  # A ranked season is exactly "season-<expansion>-<number>" with no suffix.
  RANKED_SLUG = /\Aseason-[a-z]+-\d+\z/

  def self.ranked_slug?(slug) = RANKED_SLUG.match?(slug.to_s)

  scope :ranked, -> { where(ranked: true) }
  scope :newest_first, -> { order(starts_at: :desc) }
  # Started and not yet over. Raider.io stamps far-future ends_at on the season
  # that's live, so "ended" is a real comparison rather than a null check.
  scope :ended, ->(now = Time.current) { where(ends_at: ...now) }
  scope :unended, ->(now = Time.current) { where(ends_at: now..).or(where(ends_at: nil)) }

  def ended?(now = Time.current) = ends_at.present? && ends_at < now

  # The season actually being played: started and not yet over. `unended` alone
  # is not enough — Blizzard announces the next season's slug with a future
  # start date, so it would match two.
  def self.live(now = Time.current)
    ranked.where(starts_at: ..now).unended(now).order(starts_at: :desc).first
  end

  def display_name = short_name.presence || name.presence || slug
end
