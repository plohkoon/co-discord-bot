require "test_helper"

class WowTokenPriceJobTest < ActiveJob::TestCase
  class FakeClient
    def initialize(price:, stamp:) = (@price = price; @stamp = stamp)
    def token_index = { "price" => @price, "last_updated_timestamp" => @stamp }
  end

  def epoch_ms(time) = (time.to_i * 1000)

  def run_job(price:, at:, regions: %w[us])
    WowTokenPriceJob.perform_now(
      regions: regions,
      client_for: ->(_region) { FakeClient.new(price: price, stamp: epoch_ms(at)) }
    )
  end

  test "records the price against Blizzard's timestamp, not ours" do
    at = Time.utc(2026, 7, 27, 17, 40, 57)
    run_job(price: 2_789_420_000, at: at)

    row = WowTokenPrice.latest
    assert_equal 278_942, row.gold
    assert_equal "278,942g", row.to_gold_s
    assert_equal at, row.recorded_at
  end

  # Blizzard serves the same reading until the token actually moves, so polling
  # hourly must not manufacture hourly data points.
  test "re-polling an unchanged price adds no row" do
    at = Time.utc(2026, 7, 27, 17, 40, 57)
    3.times { run_job(price: 2_789_420_000, at: at) }

    assert_equal 1, WowTokenPrice.count
  end

  test "a new reading is recorded alongside the old one" do
    run_job(price: 2_789_420_000, at: Time.utc(2026, 7, 27, 12))
    run_job(price: 2_900_000_000, at: Time.utc(2026, 7, 27, 15))

    assert_equal 2, WowTokenPrice.count
    assert_equal 290_000, WowTokenPrice.latest.gold
  end

  test "regions are tracked separately" do
    run_job(price: 2_789_420_000, at: Time.utc(2026, 7, 27, 12), regions: %w[us eu])

    assert_equal 1, WowTokenPrice.for_region("us").count
    assert_equal 1, WowTokenPrice.for_region("eu").count
  end

  test "one region failing does not stop the others" do
    WowTokenPriceJob.perform_now(
      regions: %w[us eu],
      client_for: lambda { |region|
        raise BattleNet::Client::Error, "boom" if region == "us"

        FakeClient.new(price: 3_000_000_000, stamp: epoch_ms(Time.utc(2026, 7, 27, 12)))
      }
    )

    assert_equal 0, WowTokenPrice.for_region("us").count
    assert_equal 1, WowTokenPrice.for_region("eu").count
  end

  test "change_since compares against the reading closest to that far back" do
    run_job(price: 2_500_000_000, at: Time.utc(2026, 7, 20, 12)) # a week ago
    run_job(price: 2_600_000_000, at: Time.utc(2026, 7, 26, 12)) # yesterday
    run_job(price: 2_789_420_000, at: Time.utc(2026, 7, 27, 12)) # now

    latest = WowTokenPrice.latest
    assert_equal 18_942, latest.change_since(1.day)
    assert_equal 28_942, latest.change_since(7.days)
    assert_equal "+28,942g", WowTokenPrice.format_change(latest.change_since(7.days))
  end

  # Normal for the first week after this ships — must read as "no data", not 0.
  test "change_since is nil when there is no history that far back" do
    run_job(price: 2_789_420_000, at: Time.utc(2026, 7, 27, 12))

    assert_nil WowTokenPrice.latest.change_since(7.days)
    assert_nil WowTokenPrice.format_change(nil)
  end

  test "a falling price formats as a signed decrease" do
    run_job(price: 2_900_000_000, at: Time.utc(2026, 7, 20, 12))
    run_job(price: 2_789_420_000, at: Time.utc(2026, 7, 27, 12))

    assert_equal "−11,058g", WowTokenPrice.format_change(WowTokenPrice.latest.change_since(1.day))
  end

  test "a malformed payload is skipped rather than stored" do
    WowTokenPriceJob.perform_now(
      regions: %w[us],
      client_for: ->(_r) { Class.new { def token_index = { "price" => nil } }.new }
    )

    assert_equal 0, WowTokenPrice.count
  end
end
