require "test_helper"

# The sweep decides *which* characters get refreshed. Its rules are cost
# controls (a linked account brings ~50 characters, mostly bank alts), so the
# thing worth pinning down is that they never permanently starve anyone.
class WowCharacterSweepJobTest < ActiveJob::TestCase
  MIN_LEVEL = WowCharacterSweepJob::MIN_LEVEL

  def account
    @account ||= users(:member).battle_net_accounts.create!(
      battle_net_id: 1, battle_tag: "Thrall#1234", region: "us", linked_at: Time.current
    )
  end

  def character(name:, level: MIN_LEVEL, refreshed_at: nil, missing_at: nil)
    account.wow_characters.create!(
      blizzard_id: name.hash.abs, name: name, realm: "Sargeras", realm_slug: "sargeras",
      level: level, refreshed_at: refreshed_at, missing_at: missing_at, verified_at: Time.current
    )
  end

  def swept
    enqueued_jobs.select { |j| j[:job] == WowCharacterRefreshJob }
                 .map { |j| j[:args].first }
  end

  test "enqueues never-refreshed characters" do
    fresh = character(name: "New")

    WowCharacterSweepJob.perform_now

    assert_equal [ fresh.id ], swept
  end

  test "skips characters refreshed recently and picks them up once stale" do
    recent = character(name: "Recent", refreshed_at: 1.hour.ago)

    WowCharacterSweepJob.perform_now
    assert_empty swept, "refreshed an hour ago is still current"

    recent.update!(refreshed_at: (WowCharacterSweepJob::REFRESH_AFTER + 1.hour).ago)
    WowCharacterSweepJob.perform_now
    assert_equal [ recent.id ], swept
  end

  test "skips low-level alts nobody quotes gear for" do
    character(name: "BankAlt", level: MIN_LEVEL - 1)
    main = character(name: "Main", level: MIN_LEVEL)

    WowCharacterSweepJob.perform_now

    assert_equal [ main.id ], swept
  end

  # Re-linking is what repairs a rename; retrying the same dead name forever
  # just burns the rate limit.
  test "skips characters Blizzard has stopped recognising" do
    character(name: "Renamed", missing_at: 1.day.ago)

    WowCharacterSweepJob.perform_now

    assert_empty swept
  end

  test "never-refreshed characters go before ones due for a routine top-up" do
    character(name: "Old", refreshed_at: 3.days.ago)
    brand_new = character(name: "New")

    WowCharacterSweepJob.perform_now(limit: 1)

    assert_equal [ brand_new.id ], swept
  end

  test "the batch cap defers the rest instead of dropping them" do
    3.times { |i| character(name: "Alt#{i}") }

    WowCharacterSweepJob.perform_now(limit: 2)
    assert_equal 2, swept.size

    # Nothing was marked done, so the next pass is free to take the remainder.
    assert_equal 3, WowCharacter.stale(before: Time.current).count
  end
end
