# Record the current WoW Token price for each region.
#
# Keyed on Blizzard's own `last_updated_timestamp`, not our fetch time, so
# polling more often than the token actually moves is a no-op rather than a
# stream of duplicate rows. Blizzard is the only source of the current price and
# serves no history, so this table is the history.
class WowTokenPriceJob < ApplicationJob
  queue_as :default

  retry_on BattleNet::Client::Error, wait: :polynomially_longer, attempts: 3

  def perform(regions: BattleNet::Client::REGIONS, client_for: nil)
    # An injected client bypasses the credential check, as in every other job
    # here. Without that this was untestable without real credentials — and so
    # passed locally and failed in CI.
    return unless client_for || BattleNet::Client.configured?

    Array(regions).each do |region|
      client = client_for ? client_for.call(region) : BattleNet::Client.app(region: region)
      record(region, client.token_index)
    rescue BattleNet::Client::Error => e
      # One region being unavailable shouldn't cost the others.
      Rails.logger.warn("[wow] token price failed for #{region}: #{e.class}: #{e.message}")
    end
  end

  private

  def record(region, payload)
    price = payload&.dig("price") or return
    stamp = payload["last_updated_timestamp"] or return

    row = WowTokenPrice.find_or_initialize_by(
      region: region.to_s, recorded_at: Time.zone.at(stamp.to_i / 1000)
    )
    return if row.persisted? # already have this reading

    row.price = price
    row.save!
    Rails.logger.info("[wow] token #{region.upcase}: #{row.to_gold_s}")
  end
end
