class BattleNetAccount < ApplicationRecord
  belongs_to :user
  has_many :wow_characters, dependent: :destroy

  validates :battle_net_id, presence: true,
                            uniqueness: { scope: :user_id, message: "is already linked to this account" }
  validates :region, presence: true, inclusion: { in: BattleNet::Client::REGIONS }
  validates :linked_at, presence: true

  # Blizzard user tokens expire after 24h and can't be refreshed, so a link goes
  # stale the moment the ceremony ends. That's fine for the data we keep —
  # character *identity* doesn't rot — but new characters only appear on
  # re-link, so the UI nudges after a while.
  RESYNC_AFTER = 30.days

  scope :recently_linked_first, -> { order(linked_at: :desc) }

  def display_name = battle_tag.presence || "Battle.net ##{battle_net_id}"

  def characters_stale? = characters_synced_at.nil? || characters_synced_at < RESYNC_AFTER.ago

  # Does the account the user proved to us match the one Discord says they've
  # linked? A mismatch isn't necessarily foul play (alt accounts are ordinary),
  # but it's worth surfacing rather than silently picking one. Returns nil when
  # Discord reports nothing to compare against.
  #
  # Compared as strings: Discord's connection id is opaque, and only Blizzard
  # promises it's the numeric account id.
  def matches_discord_connection?
    reported = user&.discord_battle_net_id
    return nil if reported.blank?

    reported.to_s == battle_net_id.to_s
  end
end
