# One (team, day) grouped morning reminder. The durable row means "a digest is
# scheduled for this team on this day"; AbsenceDigest::Timeline schedules the
# exact-timestamp job and delivers it. `sent?` makes the fire idempotent (a
# retry or post-downtime double-fire is a no-op).
class AbsenceDigest < ApplicationRecord
  include GuildScoped

  belongs_to :team

  enum :status, { pending: 0, sent: 1 }, default: :pending
end
