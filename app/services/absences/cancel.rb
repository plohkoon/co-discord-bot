module Absences
  # Cancels a call-out. No unscheduling is needed — the digest reads the live
  # active set at fire time, so a cancelled call-out simply drops out. Idempotent.
  # `cancelled_by_discord_id: nil` marks a system cancellation (a departed /
  # removed member's future call-outs, swept by Memberships::Archive).
  class Cancel
    def self.call(absence, cancelled_by_discord_id:)
      return absence if absence.cancelled?

      absence.update!(
        status: :cancelled,
        cancelled_at: Time.current,
        cancelled_by_discord_id: cancelled_by_discord_id
      )
      absence
    end
  end
end
