require "test_helper"

# The three posting jobs plus the REST backstop. They share a guild, an event
# row and a fake API, so they live in one file.
class GuildEventJobsTest < ActiveSupport::TestCase
  class FakeApi
    attr_reader :created, :deleted
    attr_accessor :event_payload, :fetch_error

    def initialize
      @created = []
      @deleted = []
      @next_id = 100
    end

    def create_message(channel_id, payload)
      @created << [ channel_id, payload ]
      { "id" => (@next_id += 1).to_s }
    end

    def delete_message(channel_id, message_id) = @deleted << [ channel_id, message_id ]

    def guild_roles(_guild_id)
      [ { "id" => "900", "name" => "Raid Team", "mentionable" => true },
        { "id" => "901", "name" => "Officers", "mentionable" => false } ]
    end

    def guild_scheduled_event(_guild_id, _event_id)
      raise fetch_error if fetch_error

      event_payload
    end
  end

  CHANNEL = 555
  EVENT_ID = 24680

  def guild
    @guild ||= Guild.sync_from_discord(id: 1, name: "Test").tap { |g| g.update!(events_channel_id: CHANNEL) }
  end

  def create_event(**attrs)
    ActsAsTenant.with_tenant(guild) do
      GuildEvent.create!({ discord_event_id: EVENT_ID, name: "Raid Night",
                           scheduled_start_time: 1.day.from_now }.merge(attrs))
    end
  end

  def setup = @api = FakeApi.new

  # --- announce ---

  test "announcing posts the bare event link and records the message" do
    event = create_event

    GuildEventAnnounceJob.perform_now(guild_id: guild.id, guild_event_id: event.id, api: @api)

    channel_id, payload = @api.created.sole
    assert_equal CHANNEL, channel_id
    # Nothing above the card — it already shows the name, time and RSVP button.
    assert_equal event.url, payload["content"]
    # Never pings, whatever the event is called.
    assert_equal [], payload["allowed_mentions"]["parse"]

    event.reload
    assert event.announced?
    assert_equal CHANNEL, event.channel_id
  end

  test "a role named in the description is pinged in the announcement" do
    event = create_event(description: "Bring flasks @Raid Team")

    GuildEventAnnounceJob.perform_now(guild_id: guild.id, guild_event_id: event.id, api: @api)

    payload = @api.created.sole.last
    assert_equal "<@&900>\n#{event.url}", payload["content"]
    # Only that role can ping — parse stays empty, so no @everyone/@here.
    assert_equal({ "parse" => [], "roles" => [ "900" ] }, payload["allowed_mentions"])
  end

  test "a role named in the description is pinged again when the event starts" do
    event = create_event(status: :active, description: "@Raid Team", channel_id: CHANNEL)

    GuildEventStartJob.perform_now(guild_id: guild.id, guild_event_id: event.id, api: @api)

    payload = @api.created.sole.last
    assert_match(/\A<@&900> 🔴 /, payload["content"])
    assert_equal [ "900" ], payload["allowed_mentions"]["roles"]
  end

  test "a non-mentionable role in the description pings nobody" do
    event = create_event(description: "@Officers @everyone heads up")

    GuildEventAnnounceJob.perform_now(guild_id: guild.id, guild_event_id: event.id, api: @api)

    payload = @api.created.sole.last
    assert_equal event.url, payload["content"] # description text never echoed
    assert_empty payload["allowed_mentions"]["roles"]
  end

  test "announcing twice posts once" do
    event = create_event(announcement_message_id: 42)

    GuildEventAnnounceJob.perform_now(guild_id: guild.id, guild_event_id: event.id, api: @api)

    assert_empty @api.created
  end

  test "an event that ended before the announcement ran is skipped" do
    event = create_event(status: :completed)

    GuildEventAnnounceJob.perform_now(guild_id: guild.id, guild_event_id: event.id, api: @api)

    assert_empty @api.created
  end

  test "announcing is a no-op once the events channel is cleared" do
    event = create_event
    guild.update!(events_channel_id: nil)

    GuildEventAnnounceJob.perform_now(guild_id: guild.id, guild_event_id: event.id, api: @api)

    assert_empty @api.created
    assert_not event.reload.announced?
  end

  test "a vanished channel is swallowed rather than retried forever" do
    event = create_event
    @api.define_singleton_method(:create_message) { |*| raise Discord::BotApi::NotFound, "gone" }

    assert_nothing_raised do
      GuildEventAnnounceJob.perform_now(guild_id: guild.id, guild_event_id: event.id, api: @api)
    end
    assert_not event.reload.announced?
  end

  # --- start ---

  test "the start post goes to the channel the announcement used" do
    event = create_event(status: :active, channel_id: 777, announcement_message_id: 1)

    GuildEventStartJob.perform_now(guild_id: guild.id, guild_event_id: event.id, api: @api)

    channel_id, payload = @api.created.sole
    assert_equal 777, channel_id
    assert_includes payload["content"], "come join in"
    assert_equal [], payload["allowed_mentions"]["parse"]
    assert event.reload.start_posted?
  end

  test "no start post for an event that already finished" do
    event = create_event(status: :completed)

    GuildEventStartJob.perform_now(guild_id: guild.id, guild_event_id: event.id, api: @api)

    assert_empty @api.created
  end

  # --- cleanup ---

  test "cleanup deletes every post and marks the event cleaned" do
    event = create_event(status: :completed, channel_id: CHANNEL, ended_at: 1.hour.ago,
                         announcement_message_id: 11, start_message_id: 12)

    GuildEventCleanupJob.perform_now(guild_id: guild.id, guild_event_id: event.id, api: @api)

    assert_equal [ [ CHANNEL, 11 ], [ CHANNEL, 12 ] ], @api.deleted
    event.reload
    assert event.cleaned_up?
    assert_nil event.announcement_message_id
    assert_nil event.start_message_id
  end

  test "cleanup skips an event that is no longer over" do
    event = create_event(status: :scheduled, channel_id: CHANNEL, announcement_message_id: 11)

    GuildEventCleanupJob.perform_now(guild_id: guild.id, guild_event_id: event.id, api: @api)

    assert_empty @api.deleted
    assert_not event.reload.cleaned_up?
  end

  test "cleanup runs twice without deleting twice" do
    event = create_event(status: :completed, channel_id: CHANNEL, announcement_message_id: 11)

    2.times { GuildEventCleanupJob.perform_now(guild_id: guild.id, guild_event_id: event.id, api: @api) }

    assert_equal 1, @api.deleted.size
  end

  test "a hand-deleted message does not block the rest of the cleanup" do
    event = create_event(status: :completed, channel_id: CHANNEL,
                         announcement_message_id: 11, start_message_id: 12)
    @api.define_singleton_method(:delete_message) do |_channel, message_id|
      raise Discord::BotApi::NotFound, "gone" if message_id == 11

      (@deleted ||= []) << message_id
    end

    GuildEventCleanupJob.perform_now(guild_id: guild.id, guild_event_id: event.id, api: @api)

    assert event.reload.cleaned_up?
  end

  # --- reconcile (the gateway backstop) ---

  test "reconciling applies the status Discord reports now" do
    event = create_event
    @api.event_payload = { "id" => EVENT_ID.to_s, "guild_id" => guild.id.to_s, "name" => "Raid Night",
                           "status" => 2, "scheduled_start_time" => event.scheduled_start_time.iso8601 }

    GuildEventReconcileJob.perform_now(guild_id: guild.id, discord_event_id: EVENT_ID, api: @api)

    assert event.reload.active?
  end

  test "an event Discord no longer knows about is cleaned up" do
    event = create_event(announcement_message_id: 11)
    @api.fetch_error = Discord::BotApi::NotFound.new("gone")

    GuildEventReconcileJob.perform_now(guild_id: guild.id, discord_event_id: EVENT_ID, api: @api)

    assert event.reload.canceled?
  end
end
