# Record the live season's Mythic+ score percentiles.
#
# Daily, unlike the weekly static-data sync: cutoffs drift continuously as the
# ladder fills, Blizzard publishes no M+ cutoffs at all, and a bar not captured
# while it was live cannot be reconstructed afterwards.
class RaiderIoCutoffsJob < ApplicationJob
  queue_as :default

  retry_on RaiderIo::Client::Error, wait: :polynomially_longer, attempts: 3

  def perform(client: nil, season: nil)
    RaiderIo::SyncCutoffs.call(**{ client: client, season: season }.compact)
  end
end
