require "test_helper"

class MemberJoinReconcileJobTest < ActiveSupport::TestCase
  setup { @guild = Guild.sync_from_discord(id: 42, name: "Raid Server") }

  def perform(guild_id:)
    MemberJoinReconcileJob.perform_now(guild_id: guild_id, discord_user_id: 11)
  end

  test "runs the reconcile for an installed guild" do
    calls = []
    stub_singleton_method(Memberships::JoinReconcile, :call, ->(**kwargs) { calls << kwargs }) do
      perform(guild_id: @guild.id)
    end

    assert_equal [ { guild: @guild, discord_user_id: 11 } ], calls
  end

  test "an unknown or removed guild is a no-op" do
    @guild.mark_removed!

    calls = []
    stub_singleton_method(Memberships::JoinReconcile, :call, ->(**kwargs) { calls << kwargs }) do
      perform(guild_id: @guild.id)
      perform(guild_id: 999)
    end

    assert_empty calls
  end
end
