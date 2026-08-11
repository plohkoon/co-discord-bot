require "test_helper"

# The guild time zone (anchors call-out days + the morning digest) is Manage
# Server only.
class GuildSettingsTest < ActionDispatch::IntegrationTest
  setup do
    @guild = Guild.create!(id: 555_000_111_222_333_444, name: "Raid Server")
  end

  test "a manager can set the time zone" do
    sign_in_as users(:member), manageable: [ @guild ]

    patch guild_path(@guild), params: { guild: { time_zone: "America/New_York" } }

    assert_redirected_to guild_path(@guild)
    assert_equal "America/New_York", @guild.reload.time_zone
  end

  test "a plain member cannot change the time zone" do
    sign_in_as users(:member), member: [ @guild ]

    patch guild_path(@guild), params: { guild: { time_zone: "America/New_York" } }

    assert_redirected_to guild_path(@guild)
    assert_equal "UTC", @guild.reload.time_zone
  end

  test "an unknown time zone is rejected, not silently stored as UTC" do
    sign_in_as users(:member), manageable: [ @guild ]

    patch guild_path(@guild), params: { guild: { time_zone: "Mars/Olympus" } }

    assert_redirected_to guild_path(@guild)
    assert_equal "UTC", @guild.reload.time_zone # unchanged — garbage refused
  end

  test "a manager can set and clear the public page's invite link" do
    sign_in_as users(:member), manageable: [ @guild ]

    patch guild_path(@guild), params: { guild: { invite_url: " https://discord.gg/abc123 " } }
    assert_redirected_to guild_path(@guild)
    assert_equal "https://discord.gg/abc123", @guild.reload.invite_url

    patch guild_path(@guild), params: { guild: { invite_url: "" } }
    assert_nil @guild.reload.invite_url
  end

  test "a non-Discord invite URL is rejected" do
    sign_in_as users(:member), manageable: [ @guild ]

    [ "https://evil.example/join", "javascript:alert(1)", "discord.gg/abc" ].each do |bad|
      patch guild_path(@guild), params: { guild: { invite_url: bad } }

      assert_redirected_to guild_path(@guild)
      assert_nil @guild.reload.invite_url
    end
  end

  test "a plain member cannot set the invite link" do
    sign_in_as users(:member), member: [ @guild ]

    patch guild_path(@guild), params: { guild: { invite_url: "https://discord.gg/abc123" } }

    assert_redirected_to guild_path(@guild)
    assert_nil @guild.reload.invite_url
  end
end
