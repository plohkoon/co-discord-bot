require "test_helper"

# The gateway seam for member joins: the handler does no REST — it checks for
# active memberships and enqueues MemberJoinReconcileJob, which does the role
# work off the dispatch thread. allocate skips the real bot connection.
class MemberJoinDispatchTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  FakeServer = Struct.new(:id, :name)

  setup do
    @guild = Guild.sync_from_discord(id: 42, name: "Raid Server")
    @team = ActsAsTenant.with_tenant(@guild) do
      Team.create!(name: "Alpha", team_role_id: 5, officer_role_id: 6, review_channel_id: 7)
    end
    @runner = CoBot::Runner.allocate
  end

  def dispatch(user_id: 11, server: FakeServer.new(@guild.id, @guild.name))
    @runner.send(:enqueue_join_reconcile, server: server, user_id: user_id)
  end

  def create_membership(status:)
    ActsAsTenant.with_tenant(@guild) do
      TeamMembership.create!(team: @team, discord_user_id: 11, discord_username: "recruit", status: status)
    end
  end

  test "a joiner with an active membership enqueues the reconcile job" do
    create_membership(status: :active)

    assert_enqueued_with(job: MemberJoinReconcileJob,
                         args: [ { guild_id: @guild.id, discord_user_id: 11 } ]) do
      dispatch
    end
  end

  test "a joiner with no memberships enqueues nothing" do
    assert_no_enqueued_jobs { dispatch }
  end

  test "pending and archived memberships don't enqueue" do
    create_membership(status: :pending)

    assert_no_enqueued_jobs { dispatch }
  end

  test "an unknown guild or missing ids are dropped" do
    assert_no_enqueued_jobs do
      dispatch(server: FakeServer.new(999, "Elsewhere"))
      dispatch(server: nil)
      dispatch(user_id: nil)
    end
  end
end
