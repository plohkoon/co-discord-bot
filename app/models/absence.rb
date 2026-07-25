class Absence < ApplicationRecord
  include GuildScoped

  belongs_to :team
  belongs_to :team_membership, optional: true

  enum :status, { active: 0, cancelled: 1 }, default: :active

  validates :absence_on, presence: true
  validates :discord_user_id, presence: true

  # Everyone still out (the digest reads the *live* active set at fire time).
  # The floor defaults to *today in the guild's zone* — not the app's UTC — so a
  # same-day call-out in a western guild doesn't drop early or escape the
  # departed-member cleanup in Memberships::Archive.
  scope :upcoming, ->(from = nil) { where("absence_on >= ?", from || ActsAsTenant.current_tenant&.tz&.today || Date.current) }
  scope :on, ->(date) { where(absence_on: date) }
  scope :for_user, ->(id) { where(discord_user_id: id) }

  def mention = "<@#{discord_user_id}>"
end
