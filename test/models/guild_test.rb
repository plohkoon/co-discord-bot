require "test_helper"

class GuildTest < ActiveSupport::TestCase
  test "sync_from_discord creates a guild and updates the name" do
    guild = Guild.sync_from_discord(id: 42, name: "First")
    assert guild.persisted?
    assert_equal "First", guild.name

    Guild.sync_from_discord(id: 42, name: "Renamed")
    assert_equal "Renamed", guild.reload.name
    assert_equal 1, Guild.where(id: 42).count
  end

  test "sync_from_discord clears removed_at on re-join" do
    guild = Guild.sync_from_discord(id: 42, name: "Server")
    guild.mark_removed!
    assert guild.reload.removed?

    Guild.sync_from_discord(id: 42)
    assert_not guild.reload.removed?
  end

  test "mark_removed! stamps removed_at and keeps the original timestamp on repeat calls" do
    guild = Guild.sync_from_discord(id: 42, name: "Server")
    guild.mark_removed!
    first = guild.reload.removed_at
    assert first.present?

    guild.mark_removed!
    assert_equal first, guild.reload.removed_at
  end

  test "installed and removed scopes partition guilds" do
    installed = Guild.sync_from_discord(id: 1, name: "In")
    removed = Guild.sync_from_discord(id: 2, name: "Out")
    removed.mark_removed!

    assert_equal [ installed.id ], Guild.installed.pluck(:id)
    assert_equal [ removed.id ], Guild.removed.pluck(:id)
  end

  test "log_channel_id_for uses each level's own channel when both are set" do
    guild = Guild.new(important_log_channel_id: 111, log_channel_id: 222)
    assert_equal 111, guild.log_channel_id_for(:high)
    assert_equal 222, guild.log_channel_id_for(:low)
  end

  test "log_channel_id_for collapses onto the only configured channel" do
    high_only = Guild.new(important_log_channel_id: 111)
    assert_equal 111, high_only.log_channel_id_for(:high)
    assert_equal 111, high_only.log_channel_id_for(:low) # low falls back to the important channel

    low_only = Guild.new(log_channel_id: 222)
    assert_equal 222, low_only.log_channel_id_for(:high) # high falls back to the log channel
    assert_equal 222, low_only.log_channel_id_for(:low)
  end

  test "log_channel_id_for is nil when neither channel is set" do
    guild = Guild.new
    assert_nil guild.log_channel_id_for(:high)
    assert_nil guild.log_channel_id_for(:low)
  end

  test "logging_enabled? is true when either channel is set" do
    assert_not Guild.new.logging_enabled?
    assert Guild.new(log_channel_id: 222).logging_enabled?
    assert Guild.new(important_log_channel_id: 111).logging_enabled?
  end
end
