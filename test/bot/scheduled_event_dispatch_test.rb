require "test_helper"

# The gateway seam for native scheduled events. discordrb 3.8 models none of
# them, so the runner receives raw payload hashes and routes them itself —
# allocate skips the real bot connection that #initialize would open.
class ScheduledEventDispatchTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  EVENT_ID = 13579

  setup do
    @guild = Guild.sync_from_discord(id: 42, name: "Raid Server")
    @guild.update!(events_channel_id: 900)
    @runner = CoBot::Runner.allocate
  end

  def payload(status: 1)
    { "id" => EVENT_ID.to_s, "guild_id" => @guild.id.to_s, "name" => "Raid Night",
      "status" => status, "scheduled_start_time" => 1.day.from_now.iso8601 }
  end

  def dispatch(type, data) = @runner.send(:dispatch_scheduled_event, type, data)

  def event = ActsAsTenant.with_tenant(@guild) { GuildEvent.find_by(discord_event_id: EVENT_ID) }

  test "CREATE mirrors the event under the payload's own guild" do
    dispatch("GUILD_SCHEDULED_EVENT_CREATE", payload)

    assert_equal "Raid Night", event.name
    assert_equal @guild.id, event.guild_id
  end

  test "UPDATE applies the new status" do
    dispatch("GUILD_SCHEDULED_EVENT_CREATE", payload)
    dispatch("GUILD_SCHEDULED_EVENT_UPDATE", payload(status: 2))

    assert event.active?
  end

  test "DELETE cancels the event and queues cleanup" do
    dispatch("GUILD_SCHEDULED_EVENT_CREATE", payload)
    ActsAsTenant.with_tenant(@guild) { event.update!(announcement_message_id: 5) }

    assert_enqueued_with(job: GuildEventCleanupJob) do
      dispatch("GUILD_SCHEDULED_EVENT_DELETE", payload)
    end
    assert event.canceled?
  end

  test "a payload for an unknown guild is dropped" do
    assert_nothing_raised do
      dispatch("GUILD_SCHEDULED_EVENT_CREATE", payload.merge("guild_id" => "999999"))
    end
    assert_equal 0, GuildEvent.unscoped.where(guild_id: 999999).count
  end

  test "a guild the bot was removed from is dropped" do
    @guild.mark_removed!

    dispatch("GUILD_SCHEDULED_EVENT_CREATE", payload)

    assert_nil event
  end

  test "the dispatch filter matches exactly the three event types we handle" do
    matcher = CoBot::Runner::SCHEDULED_EVENT_DISPATCH

    %w[GUILD_SCHEDULED_EVENT_CREATE GUILD_SCHEDULED_EVENT_UPDATE GUILD_SCHEDULED_EVENT_DELETE].each do |type|
      assert_match matcher, type
    end
    # RSVP traffic is intentionally ignored.
    %w[GUILD_SCHEDULED_EVENT_USER_ADD GUILD_SCHEDULED_EVENT_USER_REMOVE MESSAGE_CREATE].each do |type|
      assert_no_match matcher, type
    end
  end
end
