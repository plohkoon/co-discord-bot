class WowCharacter < ApplicationRecord
  # A character belongs to a person. The Battle.net account is *evidence* of
  # that, not the relationship itself — a character can be claimed by someone
  # who has never linked, which is the whole point of `claimed_at`.
  belongs_to :user
  belongs_to :battle_net_account, optional: true

  # A character reached through a Battle.net account inherits its owner and
  # region — both are implied by the account, and requiring callers to restate
  # them would just be a way to get them wrong. A claimed character has no
  # account and must supply both itself.
  before_validation :inherit_from_battle_net_account

  # One row per real character. Blizzard's id is globally unique, so a claim and
  # a later OAuth verification converge on the same row rather than forking.
  validates :blizzard_id, presence: true, uniqueness: true
  validates :name, :realm, :realm_slug, presence: true
  validates :region, presence: true, inclusion: { in: BattleNet::Client::REGIONS }

  # Raider.io history. Both are append-mostly: a finished season or a closed
  # raid tier never changes again, so rows are fetched once and then only read.
  has_many :wow_character_seasons, dependent: :destroy
  has_many :wow_character_raids, dependent: :destroy
  # Warcraft Logs parses, same append-mostly shape: a frozen tier is history.
  has_many :warcraft_logs_rankings, dependent: :destroy
  # PvP ratings. Append-only out of necessity rather than thrift: Blizzard
  # serves the current season only, so these rows are the sole record a past
  # season ever existed.
  has_many :wow_character_pvp_ratings, dependent: :destroy
  # Career credentials (AOTC, Cutting Edge, Gladiator). Slow-moving and heavy to
  # fetch, so refreshed on their own cadence.
  has_many :wow_character_achievements, dependent: :destroy
  has_many :wow_character_professions, dependent: :destroy
  has_many :wow_character_recipes, dependent: :delete_all
  has_many :wow_recipes, through: :wow_character_recipes


  # --- Ownership and trust ---
  #
  # Two independent facts, not one status: a claimed character that is later
  # verified is both, and telling them apart is exactly what a reviewer needs.

  scope :verified, -> { where.not(verified_at: nil) }
  # Asserted by a person, never confirmed by Blizzard. Real data, weaker claim.
  scope :unverified, -> { where(verified_at: nil) }
  scope :claimed, -> { where.not(claimed_at: nil) }
  scope :for_user, ->(user) { where(user: user) }
  scope :by_prominence, -> { order(level: :desc, name: :asc) }

  # --- Refresh (see WowCharacterSweepJob) ---

  # Worth spending requests on. Characters Blizzard has stopped recognising are
  # excluded: re-linking is what repairs those, not retrying.
  scope :refreshable, ->(min_level: 0) { where(missing_at: nil).where(level: min_level..) }
  scope :stale, ->(before:) { where(refreshed_at: ...before).or(where(refreshed_at: nil)) }
  # Never-refreshed first, then oldest — so a new link fills in before an old
  # character gets its routine top-up.
  scope :oldest_first, -> { order(Arel.sql("refreshed_at IS NULL DESC"), refreshed_at: :asc) }
  scope :missing, -> { where.not(missing_at: nil) }

  # "Thrall-Illidan" — the form players actually use, and the key Raider.io and
  # Warcraft Logs take. Not a database key: renames and transfers change it.
  def full_name = "#{name}-#{realm}"

  def verified? = verified_at.present?

  # The user said this is theirs; Blizzard has not confirmed it.
  def claimed? = claimed_at.present?

  # How much weight this character's data should carry. Anything showing a
  # character to a third party (an application reviewer, say) needs to render
  # this rather than presenting an unproven claim as fact.
  def ownership = verified? ? :verified : :claimed

  def proven? = verified?

  # Blizzard no longer recognises the name we have. Almost always a rename or
  # realm transfer rather than a deletion — the public endpoint is addressed by
  # name, so we can't follow it. Re-linking repairs it.
  def missing? = missing_at.present?

  def refreshed? = refreshed_at.present?

  # The number players quote. average_item_level counts what's in the bags too,
  # which is the one Blizzard's own armory shows.
  def ilvl = average_item_level || item_level

  def spec_and_class = [ active_spec, playable_class ].compact.join(" ").presence

  # --- Raider.io ---

  # Blizzard's rating is authoritative, but Raider.io's is the number players
  # quote and it usually lands sooner after a key. Prefer it, fall back to
  # Blizzard's. Shown whole, as scores conventionally are.
  #
  # Zero is "no keys this season", not a score: Raider.io reports 0 rather than
  # omitting the field, and 0 is truthy in Ruby — left alone it renders a "0 M+"
  # badge on every alt and lets an empty Raider.io season mask a real Blizzard
  # rating.
  def mythic_score = (scored(raider_io_score) || scored(mythic_rating))&.round

  # tank | healer | dps — what a lead actually sorts by when filling a team, and
  # the one field Blizzard doesn't expose (it gives the spec, not its role).
  def role = raider_io_role.presence

  # The live season's row — the only one that ever needs re-fetching.
  def current_season
    wow_character_seasons.detect { |s| !s.final? } ||
      wow_character_seasons.newest_first.first
  end

  def score_for(role_name) = current_season&.score_for(role_name)&.round

  # Every season we've ever recorded, newest first. This is the point of the
  # satellite table: "2900+ for three straight seasons" is a far better
  # recruiting signal than one current number.
  def season_history = wow_character_seasons.newest_first.select(&:scored?)

  def peak_score = wow_character_seasons.filter_map(&:score).max

  # Best progress first, so the headline tier leads.
  def raid_progress = wow_character_raids.attempted.best_first

  def raid_progress_headline = raid_progress.first&.summary

  # --- Warcraft Logs ---

  # Warcraft Logs has never seen them — they've never been in a logged raid.
  # True of most alts and plenty of mains; not a failure.
  def logs_missing? = warcraft_logs_missing_at.present?

  # Their strongest raid credential: hardest difficulty, then best parse, then
  # most kills.
  #
  # The kill count is the tie-break rather than decoration. Measured on a real
  # raider: a 99 Mythic off 5 kills in a one-boss raid and a 99 Mythic off 143
  # kills in the main nine-boss tier scored identically on the first two, and
  # the one-boss raid was winning on nothing but a higher zone id. More kills at
  # the same parse is the stronger claim, which is the same reason `summary`
  # carries the count.
  def best_ranking
    warcraft_logs_rankings.with_kills.newest_first
                          .max_by { |r| [ r.difficulty, r.headline || 0, r.total_kills.to_i ] }
  end

  # The headline recruiting number: their typical parse in the current tier.
  def parse = best_ranking&.headline

  def ranking_history = warcraft_logs_rankings.with_kills.newest_first

  # --- PvP ---

  def pvp? = wow_character_pvp_ratings.rated.any?

  # Their best current-season rating across every bracket — the single number
  # to lead with when there are several.
  def best_pvp_rating(season_id = WowPvpSeason.current&.blizzard_id)
    return nil if season_id.blank?

    wow_character_pvp_ratings.for_season(season_id).rated.best_first.first
  end

  def pvp_rating = best_pvp_rating&.rating

  # Every rated bracket this season, best first. Usually several, because Solo
  # Shuffle and Blitz are rated per specialisation.
  def pvp_ratings(season_id = WowPvpSeason.current&.blizzard_id)
    return WowCharacterPvpRating.none if season_id.blank?

    wow_character_pvp_ratings.for_season(season_id).rated.best_first
  end

  # --- Career achievements ---

  # "Cutting Edge: Dimensius (Apr 2024)" — the strongest PvE credential they
  # hold, newest first. Cutting Edge outranks AOTC, hence the category order.
  def best_raid_credential
    wow_character_achievements.in_category("cutting_edge").newest_first.first ||
      wow_character_achievements.in_category("aotc").newest_first.first
  end

  def raid_credentials = wow_character_achievements.raid_credentials.newest_first

  def pvp_credentials = wow_character_achievements.pvp_credentials.newest_first

  def gladiator? = wow_character_achievements.in_category("gladiator").any? ||
                   wow_character_achievements.where(blizzard_id: 2091).any?

  def cutting_edge? = wow_character_achievements.in_category("cutting_edge").any?

  def aotc? = wow_character_achievements.in_category("aotc").any?

  # --- Professions ---

  def professions = wow_character_professions.by_name

  def primary_professions = wow_character_professions.primary.by_name

  # "Engineering 100/100 · Alchemy 45/100" — the primaries, which are the two
  # that were actually chosen.
  def profession_summary = primary_professions.map(&:summary).join(" · ").presence

  def profession?(name) = wow_character_professions.named(name).any?

  def knows_recipe?(recipe_id) = wow_character_recipes.exists?(recipe_id: recipe_id)

  def known_recipe_count = wow_character_recipes.count

  # --- Outbound URLs ---
  # Everything downstream (Raider.io, Warcraft Logs, the Armory) addresses
  # characters by region + realm slug + name, so keep one place that knows how
  # to build those.
  #
  # Names are percent-encoded, not interpolated raw: accented characters are
  # ordinary in WoW ("Jörmûngandr", "Tìämat") and a browser will tidy them up in
  # an href, but an HTTP client fed the raw string will not. Blizzard wants the
  # name lowercased; Raider.io preserves case.
  def armory_url
    "https://worldofwarcraft.blizzard.com/en-us/character/#{region}/#{realm_slug}/#{url_name(downcase: true)}"
  end

  def raider_io_url
    "https://raider.io/characters/#{region}/#{realm_slug}/#{url_name}"
  end

  def warcraft_logs_url
    "https://www.warcraftlogs.com/character/#{region}/#{realm_slug}/#{url_name}"
  end

  private

  # A rating only counts as a score if it's above zero. Role scores keep their
  # zeroes — "0 dps score" is meaningful next to a real tank score.
  def scored(rating)
    rating if rating&.positive?
  end

  def inherit_from_battle_net_account
    return if battle_net_account.nil?

    self.user_id ||= battle_net_account.user_id
    self.region ||= battle_net_account.region
  end

  def url_name(downcase: false)
    URI.encode_uri_component(downcase ? name.downcase : name)
  end
end
