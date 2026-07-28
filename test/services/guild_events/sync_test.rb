require "test_helper"

class GuildEvents::SyncTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  EVENT_ID = 998877
  CHANNEL = 4242

  def guild
    @guild ||= Guild.sync_from_discord(id: 1, name: "Test").tap { |g| g.update!(events_channel_id: CHANNEL) }
  end

  def payload(status: 1, start_at: 2.days.from_now, end_at: nil, name: "Raid Night", description: nil)
    {
      "id" => EVENT_ID.to_s,
      "guild_id" => guild.id.to_s,
      "name" => name,
      "description" => description,
      "status" => status,
      "scheduled_start_time" => start_at&.iso8601,
      "scheduled_end_time" => end_at&.iso8601
    }
  end

  def event = ActsAsTenant.with_tenant(guild) { GuildEvent.find_by(discord_event_id: EVENT_ID) }

  test "a new scheduled event is mirrored and queued for announcement" do
    assert_enqueued_with(job: GuildEventAnnounceJob) do
      GuildEvents::Sync.call(guild: guild, payload: payload)
    end

    assert_equal "Raid Night", event.name
    assert event.scheduled?
  end

  test "the description is kept current so a late edit still decides the start ping" do
    GuildEvents::Sync.call(guild: guild, payload: payload(description: "@Raid Team"))
    assert_equal "@Raid Team", event.description

    GuildEvents::Sync.call(guild: guild, payload: payload(description: "@Raid Team Lead"))
    assert_equal "@Raid Team Lead", event.description
  end

  test "a guild with no events channel is ignored entirely" do
    guild.update!(events_channel_id: nil)

    assert_no_enqueued_jobs do
      GuildEvents::Sync.call(guild: guild, payload: payload)
    end
    assert_nil event
  end

  test "re-delivery of the same payload does not queue a second announcement" do
    GuildEvents::Sync.call(guild: guild, payload: payload)
    ActsAsTenant.with_tenant(guild) { event.update!(announcement_message_id: 1) }

    assert_no_enqueued_jobs(only: GuildEventAnnounceJob) do
      GuildEvents::Sync.call(guild: guild, payload: payload)
    end
  end

  test "going ACTIVE queues the start post exactly once" do
    GuildEvents::Sync.call(guild: guild, payload: payload)

    assert_enqueued_with(job: GuildEventStartJob) do
      GuildEvents::Sync.call(guild: guild, payload: payload(status: 2))
    end
    assert event.active?

    ActsAsTenant.with_tenant(guild) { event.update!(start_message_id: 7) }
    assert_no_enqueued_jobs(only: GuildEventStartJob) do
      GuildEvents::Sync.call(guild: guild, payload: payload(status: 2))
    end
  end

  test "completing schedules cleanup an hour after the end, once" do
    freeze_time do
      GuildEvents::Sync.call(guild: guild, payload: payload)
      ActsAsTenant.with_tenant(guild) { event.update!(announcement_message_id: 1) }

      GuildEvents::Sync.call(guild: guild, payload: payload(status: 3))

      assert event.completed?
      assert_equal Time.current, event.ended_at
      assert_enqueued_with(job: GuildEventCleanupJob, at: Time.current + GuildEvents::Sync::CLEANUP_DELAY)
    end
  end

  test "an event that ended without ever being posted queues nothing" do
    assert_no_enqueued_jobs(only: [ GuildEventAnnounceJob, GuildEventStartJob, GuildEventCleanupJob ]) do
      GuildEvents::Sync.call(guild: guild, payload: payload(status: 3))
    end
    assert event.completed?
  end

  test "backstop reconciles are scheduled just after the event's own timestamps" do
    start_at = 2.days.from_now.change(usec: 0)
    end_at = start_at + 3.hours

    GuildEvents::Sync.call(guild: guild, payload: payload(start_at: start_at, end_at: end_at))

    grace = GuildEvents::Sync::BACKSTOP_GRACE
    assert_enqueued_with(job: GuildEventReconcileJob, at: start_at + grace)
    assert_enqueued_with(job: GuildEventReconcileJob, at: end_at + grace)
  end

  test "an unchanged schedule does not pile up more backstops" do
    GuildEvents::Sync.call(guild: guild, payload: payload)

    assert_no_enqueued_jobs(only: GuildEventReconcileJob) do
      GuildEvents::Sync.call(guild: guild, payload: payload)
    end
  end

  test "a deleted event is cleaned up immediately rather than after the grace hour" do
    GuildEvents::Sync.call(guild: guild, payload: payload)
    ActsAsTenant.with_tenant(guild) { event.update!(announcement_message_id: 1) }

    assert_enqueued_with(job: GuildEventCleanupJob) do
      GuildEvents::Sync.deleted(guild: guild, discord_event_id: EVENT_ID)
    end

    assert event.canceled?
    assert event.ended_at.present?
  end

  test "events are scoped to their own guild" do
    other = Guild.sync_from_discord(id: 2, name: "Other")
    other.update!(events_channel_id: 9)

    GuildEvents::Sync.call(guild: guild, payload: payload)
    GuildEvents::Sync.call(guild: other, payload: payload.merge("guild_id" => other.id.to_s))

    assert_equal 1, ActsAsTenant.with_tenant(guild) { GuildEvent.count }
    assert_equal 1, ActsAsTenant.with_tenant(other) { GuildEvent.count }
  end
end
