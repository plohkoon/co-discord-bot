# Tombstone. The 7-day auto-reject used to be a per-application job scheduled at
# submit time; it now rides along on the daily ReviewDigestSweepJob, which
# retires anything past its deadline. This class stays for a release so jobs
# already queued in production deserialize and retire quietly instead of
# failing forever. Safe to delete once the queue has drained past 7 days.
class ApplicationAutoRejectJob < ApplicationJob
  queue_as :default

  def perform(*, **) = nil
end
