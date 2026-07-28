require "test_helper"

# Events-channel config on the guild page. Same rules as the log channels:
# Manage Server only, and the submitted id must come from the server's real
# channel list.
class GuildEventsChannelTest < ActionDispatch::IntegrationTest
  setup do
    @guild = Guild.create!(id: 555_000_111_222_333_444, name: "Raid Server")
  end

  # Stands in for Discord::BotApi. configured? is false so the show page's
  # GuildHealth check short-circuits without any real HTTP.
  class FakeApi
    def initialize(channels) = @channels = channels
    def configured? = false
    def guild_channels(_id) = @channels
  end

  CHANNELS = [
    { "type" => 0, "name" => "events", "id" => "111", "position" => 1 },
    { "type" => 2, "name" => "voice",  "id" => "333", "position" => 2 } # non-text, filtered out
  ].freeze

  def with_fake_api(&block)
    stub_singleton_method(Discord::BotApi, :new, FakeApi.new(CHANNELS), &block)
  end

  test "a manager sees the events-channel form" do
    sign_in_as users(:member), manageable: [ @guild ]

    with_fake_api { get guild_path(@guild) }

    assert_response :success
    assert_select "h2", text: /Events channel/
    assert_select "select[name='guild[events_channel_id]'] option[value=?]", "111"
    assert_select "select[name='guild[events_channel_id]'] option[value=?]", "333", count: 0
  end

  test "members don't see the events-channel form" do
    sign_in_as users(:member), member: [ @guild ]

    get guild_path(@guild)

    assert_response :success
    assert_select "h2", text: /Events channel/, count: 0
  end

  test "a manager can set and clear the events channel" do
    sign_in_as users(:member), manageable: [ @guild ]

    with_fake_api { patch guild_path(@guild), params: { guild: { events_channel_id: "111" } } }
    assert_redirected_to guild_path(@guild)
    assert_equal 111, @guild.reload.events_channel_id
    assert @guild.events_enabled?

    with_fake_api { patch guild_path(@guild), params: { guild: { events_channel_id: "" } } }
    assert_nil @guild.reload.events_channel_id
    assert_not @guild.events_enabled?
  end

  test "a channel outside the server's list is rejected" do
    sign_in_as users(:member), manageable: [ @guild ]

    with_fake_api { patch guild_path(@guild), params: { guild: { events_channel_id: "999" } } }

    assert_redirected_to guild_path(@guild)
    assert_nil @guild.reload.events_channel_id
  end

  test "a member cannot set the events channel" do
    sign_in_as users(:member), member: [ @guild ]

    patch guild_path(@guild), params: { guild: { events_channel_id: "111" } }

    assert_nil @guild.reload.events_channel_id
  end
end
