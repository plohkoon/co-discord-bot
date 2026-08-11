# Keep the shared Mythic+ season and raid-tier reference tables current.
#
# Slow-moving by design — a new expansion is the only thing that really changes
# the answer — but it has to run *before* the character refresh can be clever:
# knowing a season's end date is what tells RaiderIo::RefreshCharacter that its
# scores are frozen and never need fetching again.
class RaiderIoStaticDataJob < ApplicationJob
  queue_as :default

  retry_on RaiderIo::Client::Error, wait: :polynomially_longer, attempts: 3

  def perform(client: nil)
    RaiderIo::SyncStaticData.call(**{ client: client }.compact)
  end
end
