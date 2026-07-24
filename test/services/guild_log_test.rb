require "test_helper"

class GuildLogTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  test "enqueues GuildLogJob with primitive args when the level has a channel" do
    guild = Guild.create!(id: 1, name: "Test", log_channel_id: 222)

    assert_enqueued_with(job: GuildLogJob,
                         args: [ { guild_id: 1, level: :low, title: "Hi", description: nil,
                                   fields: [], actor_id: nil, color: nil } ]) do
      GuildLog.record(guild: guild, level: :low, title: "Hi")
    end
  end

  test "high collapses onto the only (low) channel, so it still enqueues" do
    guild = Guild.create!(id: 1, name: "Test", log_channel_id: 222)

    assert_enqueued_jobs 1, only: GuildLogJob do
      GuildLog.record(guild: guild, level: :high, title: "Alert")
    end
  end

  test "is a quiet no-op when the level has no channel" do
    guild = Guild.create!(id: 1, name: "Test") # no channels configured

    assert_no_enqueued_jobs do
      GuildLog.record(guild: guild, level: :high, title: "Alert")
    end
  end

  test "is a no-op when the guild is nil" do
    assert_no_enqueued_jobs do
      GuildLog.record(guild: nil, level: :low, title: "Hi")
    end
  end

  test "rejects an unknown level (a programming error) before enqueuing" do
    guild = Guild.create!(id: 1, name: "Test", log_channel_id: 222)

    assert_no_enqueued_jobs do
      assert_raises(ArgumentError) { GuildLog.record(guild: guild, level: :medium, title: "Hi") }
    end
  end
end
