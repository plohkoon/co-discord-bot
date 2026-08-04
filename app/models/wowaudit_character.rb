# One entry on a team's wowaudit roster.
#
# wowaudit is the raid leader's own list of who is on the team — maintained by
# officers, independent of Discord roles and of whether the person has ever
# linked their Battle.net account here. That independence is the point: holding
# it as its own table is what lets the three views (Discord role, wowaudit
# roster, linked characters) be compared rather than conflated.
class WowauditCharacter < ApplicationRecord
  include GuildScoped

  belongs_to :team
  # Our own record for the same character, when we have one. Nullable by
  # design — most rosters include people who have never linked Battle.net.
  belongs_to :wow_character, optional: true

  validates :wowaudit_id, presence: true, uniqueness: { scope: :team_id }
  validates :name, presence: true

  scope :matched, -> { where.not(wow_character_id: nil) }
  scope :unmatched, -> { where(wow_character_id: nil) }
  scope :by_name, -> { order(:name) }

  # "Thrall-Sargeras" when we know the realm — the form players use, and what
  # the name match keys on.
  def full_name = realm.present? ? "#{name}-#{realm}" : name

  def matched? = wow_character_id.present?

  # Name+realm is the only key wowaudit and Blizzard share here: wowaudit's
  # character ids are its own, and it doesn't publish Blizzard's. Case and
  # accents both vary between sources, so normalise before comparing.
  def self.match_key(name, realm)
    [ name.to_s.unicode_normalize(:nfc).downcase, realm.to_s.unicode_normalize(:nfc).downcase.tr(" ", "-") ]
  end

  def match_key = self.class.match_key(name, realm)
end
