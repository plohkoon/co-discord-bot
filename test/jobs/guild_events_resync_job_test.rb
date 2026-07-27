require "test_helper"

# Moving a guild's events channel: vacate the old one, backfill the new one in
# creation order.
class GuildEventsResyncJobTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  class FakeApi
    attr_reader :created, :deleted
    attr_accessor :events

    def initialize(events: [])
      @events = events
      @created = []
      @deleted = []
      @next_id = 500
    end

    def guild_scheduled_events(_guild_id) = @events

    def create_message(channel_id, payload)
      @created << [ channel_id, payload["content"] ]
      { "id" => (@next_id += 1).to_s }
    end

    def delete_message(channel_id, message_id) = @deleted << [ channel_id, message_id ]

    def guild_roles(_guild_id) = []
  end

  OLD_CHANNEL = 111
  NEW_CHANNEL = 222

  def guild = @guild ||= Guild.sync_from_discord(id: 7, name: "Raid Server")

  # Ids are snowflakes, so a *lower* id is the older event regardless of when
  # it's scheduled to happen — 300 is created first, 400 second.
  def remote_events
    [ { "id" => "400", "guild_id" => guild.id.to_s, "name" => "Second", "status" => 1,
        "scheduled_start_time" => 3.days.from_now.iso8601 },
      { "id" => "300", "guild_id" => guild.id.to_s, "name" => "First", "status" => 1,
        "scheduled_start_time" => 2.days.from_now.iso8601 } ]
  end

  def perform(previous: nil, api:)
    GuildEventsResyncJob.perform_now(guild_id: guild.id, previous_channel_id: previous, api: api)
  end

  def events = ActsAsTenant.with_tenant(guild) { GuildEvent.order(:discord_event_id).to_a }

  test "configuring a channel for the first time backfills every live event, oldest first" do
    guild.update_column(:events_channel_id, NEW_CHANNEL)
    api = FakeApi.new(events: remote_events)

    perform(api: api)

    # Posted in creation (snowflake) order, not the order Discord listed them.
    assert_equal [ NEW_CHANNEL, NEW_CHANNEL ], api.created.map(&:first)
    assert_equal %w[300 400], api.created.map { |_channel, content| content[%r{events/\d+/(\d+)}, 1] }
    assert_equal [ 300, 400 ], events.map(&:discord_event_id)
    assert events.all?(&:announced?)
  end

  test "events that already finished are not resurrected" do
    guild.update_column(:events_channel_id, NEW_CHANNEL)
    finished = remote_events.first.merge("status" => 3)
    api = FakeApi.new(events: [ finished ])

    perform(api: api)

    assert_empty api.created
  end

  test "an event already under way gets both posts" do
    guild.update_column(:events_channel_id, NEW_CHANNEL)
    api = FakeApi.new(events: [ remote_events.last.merge("status" => 2) ])

    perform(api: api)

    assert_equal 2, api.created.size
    assert_includes api.created.last.last, "come join in"
  end

  test "changing the channel deletes the old posts and re-posts in the new one" do
    guild.update_column(:events_channel_id, NEW_CHANNEL)
    stale = ActsAsTenant.with_tenant(guild) do
      GuildEvent.create!(discord_event_id: 300, name: "First", channel_id: OLD_CHANNEL,
                         announcement_message_id: 11, start_message_id: 12)
    end
    api = FakeApi.new(events: [ remote_events.last ])

    perform(previous: OLD_CHANNEL, api: api)

    assert_equal [ [ OLD_CHANNEL, 11 ], [ OLD_CHANNEL, 12 ] ], api.deleted
    stale.reload
    assert_equal NEW_CHANNEL, stale.channel_id
    assert stale.announced?
    assert_equal NEW_CHANNEL, api.created.sole.first
  end

  test "clearing the channel takes the posts down and posts nothing new" do
    guild.update_column(:events_channel_id, nil)
    ActsAsTenant.with_tenant(guild) do
      GuildEvent.create!(discord_event_id: 300, name: "First", channel_id: OLD_CHANNEL,
                         announcement_message_id: 11)
    end
    api = FakeApi.new(events: remote_events)

    perform(previous: OLD_CHANNEL, api: api)

    assert_equal [ [ OLD_CHANNEL, 11 ] ], api.deleted
    assert_empty api.created
  end

  test "a finished event is marked cleaned up when its old posts go" do
    guild.update_column(:events_channel_id, NEW_CHANNEL)
    done = ActsAsTenant.with_tenant(guild) do
      GuildEvent.create!(discord_event_id: 300, name: "Old", status: :completed,
                         channel_id: OLD_CHANNEL, announcement_message_id: 11)
    end
    api = FakeApi.new(events: [])

    perform(previous: OLD_CHANNEL, api: api)

    assert done.reload.cleaned_up?
  end

  test "re-running does not double-post" do
    guild.update_column(:events_channel_id, NEW_CHANNEL)
    api = FakeApi.new(events: remote_events)

    2.times { perform(api: api) }

    assert_equal 2, api.created.size # two events, one post each
  end

  test "a removed guild is a no-op" do
    guild.update_column(:events_channel_id, NEW_CHANNEL)
    guild.mark_removed!
    api = FakeApi.new(events: remote_events)

    perform(api: api)

    assert_empty api.created
  end

  test "saving a new events channel enqueues the move with the previous one" do
    guild.update!(events_channel_id: OLD_CHANNEL)

    assert_enqueued_with(job: GuildEventsResyncJob,
                         args: [ { guild_id: guild.id, previous_channel_id: OLD_CHANNEL } ]) do
      guild.update!(events_channel_id: NEW_CHANNEL)
    end
  end

  test "saving an unrelated setting does not move anything" do
    guild.update!(events_channel_id: NEW_CHANNEL)

    assert_no_enqueued_jobs(only: GuildEventsResyncJob) do
      guild.update!(name: "Renamed")
    end
  end
end
