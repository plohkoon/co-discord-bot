# Keep the recipe catalog current.
#
# Monthly: a closed expansion's recipe list never changes, so the sync only
# re-reads each profession's newest tier (~50 requests) unless the catalog is
# empty or a full refresh is forced.
class WowRecipeCatalogJob < ApplicationJob
  queue_as :default

  retry_on BattleNet::Client::Error, wait: :polynomially_longer, attempts: 3

  def perform(client: nil, refresh_all: false)
    return unless client || BattleNet::Client.configured?

    BattleNet::SyncRecipeCatalog.call(**{ client: client, refresh_all: refresh_all }.compact)
  end
end
