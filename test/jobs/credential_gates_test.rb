require "test_helper"

# Every integration job refuses to run without its credentials, so co-bot works
# for a server that has configured none of them. This asserts BOTH directions of
# each gate.
#
# The second direction is the one that matters. The suite runs with every
# integration unconfigured, so "does nothing" passes trivially — including for a
# gate that is simply broken. `WowTokenPriceJob` shipped gating on
# `configured?` alone while every sibling accepted an injected client, and no
# test noticed, because nothing here ever asserted that a *configured* job
# actually proceeds.
#
# "Proceeds" is asserted by stubbing the service the job delegates to. That
# proves the gate opened without letting anything reach the network — these
# credentials are fake, so a real request would be a test that forgot to stub.
class CredentialGatesTest < ActiveJob::TestCase
  # Records that it was called, so "the gate opened" is observable.
  def spy
    calls = []
    [ calls, ->(*args, **kwargs) { calls << [ args, kwargs ] } ]
  end

  # Enough of a Blizzard client to get through a refresh without a network call.
  def blizzard_client
    Class.new do
      def character_profile(_realm, name) = { "name" => name, "level" => 90, "average_item_level" => 640 }
      def mythic_keystone_profile(*) = nil
      def pvp_summary(*) = { "honor_level" => 3 }
      def character_professions(*) = { "primaries" => [] }
    end.new
  end

  # Raider.io needs no credentials — it is public — so it has no gate and always
  # runs. It still needs a client here, or the refresh would call out for real.
  def raider_io_client
    Class.new do
      def character_profile(region:, realm:, name:, fields: nil) = {}
    end.new
  end

  # --- Blizzard ---

  test "the token price job runs when Blizzard is configured" do
    calls, recorder = spy
    with_credentials(:blizzard) do
      stub_singleton_method(BattleNet::Client, :app, ->(**) { raise "unreachable" }) do
        # client_for short-circuits the real client; the gate is what's under test.
        WowTokenPriceJob.perform_now(regions: %w[us], client_for: ->(_r) {
          Class.new { def token_index = { "price" => 1, "last_updated_timestamp" => 0 } }.new
        })
      end
    end
    assert_equal 1, WowTokenPrice.count

    WowTokenPrice.delete_all
    stub_singleton_method(BattleNet::Client, :app, recorder) do
      WowTokenPriceJob.perform_now(regions: %w[us])
    end
    assert_empty calls, "unconfigured: never reaches the client"
    assert_equal 0, WowTokenPrice.count
  end

  test "the PvP reference sync runs only when Blizzard is configured" do
    calls, recorder = spy

    stub_singleton_method(BattleNet::SyncPvpReference, :call, recorder) do
      PvpReferenceSyncJob.perform_now
      assert_empty calls, "unconfigured: no work"

      with_credentials(:blizzard) { PvpReferenceSyncJob.perform_now }
      assert_equal 1, calls.size, "configured: proceeds"
    end
  end

  test "the recipe catalog sync runs only when Blizzard is configured" do
    calls, recorder = spy

    stub_singleton_method(BattleNet::SyncRecipeCatalog, :call, recorder) do
      WowRecipeCatalogJob.perform_now
      assert_empty calls

      with_credentials(:blizzard) { WowRecipeCatalogJob.perform_now }
      assert_equal 1, calls.size
    end
  end

  # --- Warcraft Logs ---

  test "the zone sync runs only when Warcraft Logs is configured" do
    calls, recorder = spy

    stub_singleton_method(WarcraftLogs::SyncZones, :call, recorder) do
      WarcraftLogsZonesJob.perform_now
      assert_empty calls

      with_credentials(:warcraft_logs) { WarcraftLogsZonesJob.perform_now }
      assert_equal 1, calls.size
    end
  end

  test "a character refresh reaches Warcraft Logs only when it is configured" do
    character = users(:member).wow_characters.create!(
      blizzard_id: 42, name: "Thrall", realm: "Sargeras", realm_slug: "sargeras",
      region: "us", level: 90, verified_at: Time.current
    )
    calls, recorder = spy

    stub_singleton_method(WarcraftLogs::RefreshCharacter, :call, recorder) do
      WowCharacterRefreshJob.perform_now(character.id, client: blizzard_client, raider_io: raider_io_client)
      assert_empty calls, "unconfigured: the parse step is skipped entirely"

      with_credentials(:warcraft_logs) do
        WowCharacterRefreshJob.perform_now(character.id, client: blizzard_client, raider_io: raider_io_client)
      end
      assert_equal 1, calls.size, "configured: parses are gathered"
    end
  end

  # --- Degrading, not breaking ---

  # The point of every gate above: a server that has configured nothing still
  # gets the Blizzard-only data, rather than an error.
  test "a character refresh completes with no third-party credentials at all" do
    character = users(:member).wow_characters.create!(
      blizzard_id: 43, name: "Morhigahn", realm: "Sargeras", realm_slug: "sargeras",
      region: "us", level: 90, verified_at: Time.current
    )
    assert_nothing_raised do
      WowCharacterRefreshJob.perform_now(character.id, client: blizzard_client,
                                         raider_io: raider_io_client)
    end

    character.reload
    assert_equal 640, character.average_item_level
    assert_empty character.warcraft_logs_rankings
    assert_nil character.warcraft_logs_refreshed_at
  end
end
