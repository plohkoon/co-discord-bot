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
end
