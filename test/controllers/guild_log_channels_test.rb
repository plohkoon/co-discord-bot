require "test_helper"

# Log-channel config on the guild page: Manage Server only, and submitted
# channel ids must come from the server's real channel list.
class GuildLogChannelsTest < ActionDispatch::IntegrationTest
  setup do
    @guild = Guild.create!(id: 555_000_111_222_333_444, name: "Raid Server")
  end

  # Stands in for Discord::BotApi. configured? is false so the show page's
  # GuildHealth check short-circuits without any real HTTP.
  class FakeApi
    def initialize(channels) = @channels = channels
    def configured? = false
    def guild_channels(_id) = @channels
    def guild_roles(_id) = []
  end

  CHANNELS = [
    { "type" => 0, "name" => "alerts", "id" => "111", "position" => 1 },
    { "type" => 0, "name" => "audit",  "id" => "222", "position" => 2 },
    { "type" => 2, "name" => "voice",  "id" => "333", "position" => 3 } # non-text, filtered out
  ].freeze

  def with_fake_api(channels: CHANNELS, &block)
    stub_singleton_method(Discord::BotApi, :new, FakeApi.new(channels), &block)
  end

  test "a manager sees the log-channels form with only text channels" do
    sign_in_as users(:member), manageable: [ @guild ]

    with_fake_api { get guild_path(@guild) }

    assert_response :success
    assert_select "h2", text: /Log channels/
    assert_select "select[name='guild[important_log_channel_id]'] option[value=?]", "111"
    assert_select "select[name='guild[log_channel_id]'] option[value=?]", "222"
    assert_select "select[name='guild[log_channel_id]'] option[value=?]", "333", count: 0 # voice filtered
  end

  test "members don't see the log-channels form" do
    sign_in_as users(:member), member: [ @guild ]

    get guild_path(@guild)

    assert_response :success
    assert_select "h2", text: /Log channels/, count: 0
  end

  test "a manager can set both channels" do
    sign_in_as users(:member), manageable: [ @guild ]

    with_fake_api do
      patch guild_path(@guild), params: { guild: { important_log_channel_id: "111", log_channel_id: "222" } }
    end

    assert_redirected_to guild_path(@guild)
    @guild.reload
    assert_equal 111, @guild.important_log_channel_id
    assert_equal 222, @guild.log_channel_id
  end

  test "a manager can clear a channel by submitting blank" do
    @guild.update!(important_log_channel_id: 111, log_channel_id: 222)
    sign_in_as users(:member), manageable: [ @guild ]

    with_fake_api do
      patch guild_path(@guild), params: { guild: { important_log_channel_id: "111", log_channel_id: "" } }
    end

    assert_redirected_to guild_path(@guild)
    @guild.reload
    assert_equal 111, @guild.important_log_channel_id
    assert_nil @guild.log_channel_id
  end

  test "a channel id not in the server's list is rejected" do
    sign_in_as users(:member), manageable: [ @guild ]

    with_fake_api do
      patch guild_path(@guild), params: { guild: { important_log_channel_id: "999", log_channel_id: "" } }
    end

    assert_redirected_to guild_path(@guild)
    assert_match(/from the list/, flash[:alert])
    assert_nil @guild.reload.important_log_channel_id
  end

  test "a non-manager cannot set log channels" do
    sign_in_as users(:member), member: [ @guild ]

    patch guild_path(@guild), params: { guild: { log_channel_id: "222" } }

    assert_redirected_to guild_path(@guild)
    assert_match(/Manage Server/, flash[:alert])
    assert_nil @guild.reload.log_channel_id
  end
end
