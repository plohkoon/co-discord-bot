require "test_helper"

class GuildLogJobTest < ActiveSupport::TestCase
  # Records REST traffic; can simulate a delivery failure.
  class FakeApi
    attr_reader :created
    attr_accessor :create_error

    def initialize
      @created = []
    end

    def create_message(channel_id, payload)
      raise create_error if create_error

      @created << [ channel_id, payload ]
    end
  end

  def setup = @api = FakeApi.new

  def run_job(guild_id:, level: :low, **opts)
    GuildLogJob.perform_now(guild_id: guild_id, level: level, title: "Member removed", api: @api, **opts)
  end

  test "posts a color-coded embed with mentions muted to the resolved channel" do
    guild = Guild.create!(id: 1, name: "Test", log_channel_id: 222, important_log_channel_id: 111)

    run_job(guild_id: guild.id, level: :low, description: "<@42> left **Alpha**.", actor_id: 99, color: 0x99AAB5)

    assert_equal 1, @api.created.size
    channel_id, payload = @api.created.first
    assert_equal 222, channel_id # the low channel
    embed = payload["embeds"].first
    assert_equal "Member removed", embed["title"]
    assert_equal 0x99AAB5, embed["color"]
    assert_equal "<@42> left **Alpha**.", embed["description"]
    # The actor is echoed as a field, but nothing may ping.
    assert(embed["fields"].any? { |f| f["value"] == "<@99>" })
    assert_equal({ "parse" => [] }, payload["allowed_mentions"])
  end

  test "high collapses onto the only configured channel" do
    guild = Guild.create!(id: 1, name: "Test", log_channel_id: 222)

    run_job(guild_id: guild.id, level: :high, title: "Application received")

    assert_equal 222, @api.created.first.first
  end

  test "re-resolves the channel at run time — unset since enqueue is a no-op" do
    guild = Guild.create!(id: 1, name: "Test") # channels cleared after the job was enqueued

    run_job(guild_id: guild.id, level: :low)

    assert_empty @api.created
  end

  test "missing guild is a no-op" do
    run_job(guild_id: 999_999)

    assert_empty @api.created
  end

  test "swallows NotFound (deleted / unpostable channel) as a logged no-op" do
    guild = Guild.create!(id: 1, name: "Test", log_channel_id: 222)
    @api.create_error = Discord::BotApi::NotFound.new("gone")

    assert_nothing_raised { run_job(guild_id: guild.id, level: :low) }
    assert_empty @api.created
  end
end
