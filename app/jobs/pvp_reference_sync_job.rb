# Keep the PvP seasons, tiers and title cutoffs current.
#
# Daily rather than weekly, because cutoffs drift continuously as the ladder
# fills and the movement is itself the data — a changed bar becomes a new row.
class PvpReferenceSyncJob < ApplicationJob
  queue_as :default

  retry_on BattleNet::Client::Error, wait: :polynomially_longer, attempts: 3

  def perform(client: nil)
    return unless client || BattleNet::Client.configured?

    BattleNet::SyncPvpReference.call(**{ client: client }.compact)
  end
end
