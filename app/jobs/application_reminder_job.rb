# Tombstone. Officer reminders used to be per-application jobs scheduled at
# 24h/3d/6d; they're now one daily sweep (ReviewDigestSweepJob) reading the live
# rows. This class stays for a release so the jobs already sitting in the
# production queue deserialize and retire quietly instead of failing forever.
# Safe to delete once the queue has drained past the old 7-day horizon.
class ApplicationReminderJob < ApplicationJob
  queue_as :default

  def perform(*, **) = nil
end
