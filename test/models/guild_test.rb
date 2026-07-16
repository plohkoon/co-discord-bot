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
end
