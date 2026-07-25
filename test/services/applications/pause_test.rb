require "test_helper"

module Applications
  class PauseTest < ActiveSupport::TestCase
    include ActiveJob::TestHelper

    def guild = @guild ||= Guild.sync_from_discord(id: 2, name: "Pause Test")

    def with_tenant(&block) = ActsAsTenant.with_tenant(guild, &block)

    def create_application
      with_tenant do
        team = Team.create!(name: "Alpha #{SecureRandom.hex(3)}", team_role_id: 5,
                            officer_role_id: 6, review_channel_id: 7)
        membership = TeamMembership.create!(team: team, discord_user_id: 11, discord_username: "alice", status: :pending)
        membership.team_applications.create!(team: team, discord_user_id: 11, discord_username: "alice",
                                             source: :applied)
      end
    end

    test "pausing records who parked it and stops the timeline" do
      application = create_application

      result = with_tenant { Pause.pause(application: application, actor_discord_id: 99) }

      assert_equal :ok, result.status
      application.reload
      assert application.paused?
      assert application.pending?, "the status stays pending so the unique index and guards hold"
      assert_equal 99, application.paused_by_discord_id
    end

    test "pausing twice is reported, not repeated" do
      application = create_application
      with_tenant { Pause.pause(application: application, actor_discord_id: 99) }
      first_paused_at = application.reload.paused_at

      result = with_tenant { Pause.pause(application: application, actor_discord_id: 100) }

      assert_equal :already_paused, result.status
      assert_equal first_paused_at, application.reload.paused_at
      assert_equal 99, application.paused_by_discord_id
    end

    test "a decided application can't be paused, and deciding one ends the pause" do
      application = create_application
      with_tenant { application.update!(status: :rejected, decided_at: Time.current) }

      assert_equal :already_decided, with_tenant { Pause.pause(application: application, actor_discord_id: 99) }.status

      # And a row that was paused before it got decided no longer reads paused.
      other = create_application
      with_tenant { Pause.pause(application: other, actor_discord_id: 99) }
      with_tenant { other.update!(status: :accepted, decided_at: Time.current) }
      assert_not other.reload.paused?
    end

    test "resuming clears the pause and restarts the clock — with nothing to re-arm" do
      application = create_application
      with_tenant { Pause.pause(application: application, actor_discord_id: 99) }

      result = nil
      # The whole point of the daily sweep: pause/resume schedules and cancels
      # nothing, so there are no timers to get out of step with the row.
      assert_no_enqueued_jobs do
        result = with_tenant { Pause.resume(application: application) }
      end

      assert_equal :ok, result.status
      application.reload
      assert_not application.paused?
      assert_nil application.paused_by_discord_id
      assert application.timeline_started_at.present?
      assert application.timeline_start > application.created_at, "the clock restarts at the resume"
    end

    test "resuming one that isn't paused changes nothing" do
      application = create_application

      result = with_tenant { Pause.resume(application: application) }

      assert_equal :not_paused, result.status
      assert_nil application.reload.timeline_started_at
    end
  end
end
