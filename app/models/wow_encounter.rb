# A raid boss — the bridge between Raider.io's tiers and Warcraft Logs' zones.
#
# The two services carve tiers up differently (Raider.io's "MN Tier 1 (VS / DR /
# MQD)" is one nine-boss tier across three instances), so matching them at the
# tier level is guesswork. Bosses are unambiguous, and this table is where each
# service records its own view of the same boss.
#
# **On the join key.** Blizzard's journal encounter id is the rigorous key and
# both services publish the field — but only Raider.io fills it in. Verified
# live: Warcraft Logs returns `journalID: 0` for every encounter in every zone,
# current and years old alike. So the journal id is used when it's real, and a
# normalised boss name is the fallback. Names matched 8/9 in the live tier
# unmodified and 9/9 once punctuation and case are stripped.
class WowEncounter < ApplicationRecord
  belongs_to :wow_raid, foreign_key: :raid_slug, primary_key: :slug,
                        inverse_of: :wow_encounters, optional: true
  belongs_to :warcraft_logs_zone, foreign_key: :wcl_zone_id, primary_key: :wcl_id,
                                  inverse_of: :wow_encounters, optional: true

  validates :journal_id, presence: true, uniqueness: true

  # Bosses both services have told us about — the ones that actually bridge.
  scope :linked, -> { where.not(raid_slug: nil).where.not(wcl_zone_id: nil) }

  # Punctuation and case only. Deliberately conservative: this is a fallback
  # key, and collapsing more aggressively (dropping "the", say) would start
  # matching genuinely different bosses.
  def self.normalize(name)
    name.to_s.downcase.gsub(/[,'’\-.:]/, " ").squish.presence
  end

  # Record what one service knows without clobbering what the other wrote.
  # Syncs run independently and in either order, so each only fills its own
  # column.
  def self.record!(journal_id:, name: nil, raid_slug: nil, wcl_zone_id: nil)
    return false if journal_id.blank? || journal_id.to_i.zero?

    row = find_or_initialize_by(journal_id: journal_id)
    row.name = name if name.present?
    row.normalized_name = normalize(name) if name.present?
    row.raid_slug = raid_slug if raid_slug.present?
    row.wcl_zone_id = wcl_zone_id if wcl_zone_id.present?
    row.synced_at = Time.current
    row.save!
  end

  # Attach a Warcraft Logs zone to an encounter we already know about.
  #
  # Prefers the journal id — which would be exact, and will start working for
  # free if Warcraft Logs ever populates it — and falls back to the normalised
  # name. Deliberately only ANNOTATES an existing row: a boss Raider.io has
  # never mentioned has nothing to be joined to, so inventing a row for it would
  # add noise rather than a link.
  def self.link_warcraft_logs!(name:, wcl_zone_id:, journal_id: nil)
    row = find_by(journal_id: journal_id) if journal_id.to_i.positive?
    row ||= find_by(normalized_name: normalize(name))
    return false if row.nil?

    row.update!(wcl_zone_id: wcl_zone_id, synced_at: Time.current)
  end

  def linked? = raid_slug.present? && wcl_zone_id.present?
end
