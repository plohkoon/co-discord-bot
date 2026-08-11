# An admin-configured rule: "anyone whose WoW data meets this bar gets that
# Discord role". Three kinds — an exact achievement, a Mythic+ score floor, a
# PvP rating floor (optionally restricted to one bracket type).
#
# Evaluation runs USER-first, never member-first: for each rule we find
# qualifying users from the WoW tables (any of their characters counts, claimed
# or verified — ownership strength doesn't gate a role that's just a badge),
# then attempt the role grant over REST. Nothing here pages the guild member
# list — Memberships::Backfill stays the only full member scan in the app.
#
# Grant-only by default: achievements can't be un-earned, and yanking roles
# when a season resets scores would be hostile. `auto_revoke` opts a rule into
# the opposite semantic — the sweep strips the role again once the requirement
# stops holding (scores reset, characters unlinked). See RoleRewards::Evaluate.
class RoleReward < ApplicationRecord
  include GuildScoped

  has_many :role_reward_grants, dependent: :delete_all

  # `validate: true` so a hand-crafted POST with a junk kind fails validation
  # instead of raising in the controller.
  enum :kind, { achievement: "achievement", mythic_plus: "mythic_plus", pvp: "pvp" }, validate: true

  BRACKET_TYPES = (WowCharacterPvpRating::TEAM_BRACKETS + WowCharacterPvpRating::PER_SPEC_BRACKETS).freeze
  BRACKET_LABELS = { "2v2" => "2v2", "3v3" => "3v3", "rbg" => "RBG",
                     "shuffle" => "Solo Shuffle", "blitz" => "Blitz" }.freeze

  before_validation :clear_irrelevant_fields

  validates :discord_role_id, presence: true
  validates :achievement_name, presence: true, if: :achievement?
  validates :threshold, presence: true,
                        numericality: { only_integer: true, greater_than: 0 },
                        if: :threshold_kind?
  validates :pvp_bracket_type, inclusion: { in: BRACKET_TYPES }, allow_nil: true

  def threshold_kind? = mythic_plus? || pvp?

  # "Earned "Ahead of the Curve: Dimensius"" / "Mythic+ score ≥ 2500" /
  # "Solo Shuffle rating ≥ 2400" — shown in the rules list and the audit log.
  def summary
    case kind
    when "achievement" then %(earned "#{achievement_name}")
    when "mythic_plus" then "Mythic+ score ≥ #{threshold}"
    when "pvp"         then "#{bracket_label} rating ≥ #{threshold}"
    end
  end

  def bracket_label
    pvp_bracket_type.present? ? BRACKET_LABELS.fetch(pvp_bracket_type, pvp_bracket_type) : "PvP"
  end

  # Discord ids of every user who currently meets this rule, via any character
  # they own. Returns nil when the rule can't be evaluated right now (a PvP
  # rule before the season reference data exists) — callers must skip both
  # grants and revokes on nil rather than reading it as "nobody qualifies".
  def qualifying_discord_user_ids
    user_ids = qualifying_user_ids
    return nil if user_ids.nil?

    User.where(id: user_ids).pluck(:discord_id).map(&:to_i)
  end

  private

  # User ids (not discord ids) whose characters meet the rule. Cross-guild by
  # design: WoW data hangs off users, and the grant attempt is what filters to
  # this guild's members (Discord 404s for anyone not in it).
  def qualifying_user_ids
    case kind
    when "achievement" then achievement_user_ids
    when "mythic_plus" then mythic_plus_user_ids
    when "pvp"         then pvp_user_ids
    end
  end

  # Exact-match against stored names. Rows only exist for *earned*
  # achievements (RefreshCharacterAchievements skips entries with no
  # completion timestamp), so presence is the earned state.
  def achievement_user_ids
    WowCharacter.joins(:wow_character_achievements)
                .where(wow_character_achievements: { name: achievement_name })
                .distinct.pluck(:user_id)
  end

  # Mirrors WowCharacter#mythic_score: Raider.io's number wins when present,
  # Blizzard's is the fallback, and zero means "no keys this season", not a
  # score. SQL prefilters the candidates; the helper makes the final call so
  # the zero-is-absent rule lives in exactly one place.
  def mythic_plus_user_ids
    WowCharacter.where("raider_io_score >= :t OR mythic_rating >= :t", t: threshold)
                .select { |character| character.mythic_score.to_i >= threshold }
                .map(&:user_id).uniq
  end

  # Current-season ratings only — Blizzard serves nothing else, and scoping to
  # the live season is what lets auto_revoke strip roles when a season resets
  # (past-season rows are append-only history and never vanish). nil = the PvP
  # season reference hasn't synced yet, so the rule is unevaluable.
  def pvp_user_ids
    season_id = WowPvpSeason.current&.blizzard_id
    return nil if season_id.blank?

    scope = WowCharacter.joins(:wow_character_pvp_ratings)
                        .where(wow_character_pvp_ratings: { season_id: season_id, rating: threshold.. })
    scope = scope.where(wow_character_pvp_ratings: { bracket_type: pvp_bracket_type }) if pvp_bracket_type.present?
    scope.distinct.pluck(:user_id)
  end

  # Each kind keeps only its own fields, so a form that switched kinds (or a
  # crafted POST) can't leave a stale achievement name on a score rule.
  def clear_irrelevant_fields
    self.achievement_name = achievement_name.to_s.strip.presence
    self.achievement_name = nil unless achievement?
    self.threshold = nil unless threshold_kind?
    self.pvp_bracket_type = pvp_bracket_type.presence
    self.pvp_bracket_type = nil unless pvp?
  end
end
