# Keep the Warcraft Logs raid-zone reference table current.
#
# Must run before character refreshes can be cheap: a zone's `frozen` flag is
# what proves a tier's parses are final and never need fetching again. One
# GraphQL query covers every expansion, so weekly is plenty.
#
# No-op without credentials, so the rest of the WoW pipeline runs regardless.
class WarcraftLogsZonesJob < ApplicationJob
  queue_as :default

  retry_on WarcraftLogs::Client::Error, wait: :polynomially_longer, attempts: 3

  def perform(client: nil)
    return unless client || WarcraftLogs::Client.configured?

    WarcraftLogs::SyncZones.call(**{ client: client }.compact)
  end
end
