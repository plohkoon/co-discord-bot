require "test_helper"

module Applications
  class TimelineTest < ActiveSupport::TestCase
    include ActiveJob::TestHelper

    OFFICER_ROLE = 42
    CHANNEL = 900
    MESSAGE = 901

    # Records every REST call; can simulate failures.
    class FakeApi
      attr_reader :created, :edited
      attr_accessor :create_error

      def initialize
        @created = []
        @edited = []
      end

      def create_message(channel_id, payload)
        raise create_error if create_error

        @created << [ channel_id, payload ]
      end

      def edit_message(channel_id, message_id, payload)
        @edited << [ channel_id, message_id, payload ]
      end
    end

    def guild = @guild ||= Guild.sync_from_discord(id: 1, name: "Test")

    def setup
      @api = FakeApi.new
    end

    def with_tenant(&block) = ActsAsTenant.with_tenant(guild, &block)

    def create_application(submitted_at: Time.current, reminder_stage: 0)
      with_tenant do
        team = Team.create!(name: "Alpha #{SecureRandom.hex(3)}", team_role_id: 5,
                            officer_role_id: OFFICER_ROLE, review_channel_id: CHANNEL)
        membership = TeamMembership.create!(team: team, discord_user_id: 11, discord_username: "alice", status: :pending)
        membership.team_applications.create!(
          team: team, discord_user_id: 11, discord_username: "alice", source: :applied,
          review_channel_id: CHANNEL, review_message_id: MESSAGE,
          created_at: submitted_at, reminder_stage: reminder_stage
        )
      end
    end

    def remind(application, stage:, now:)
      with_tenant { Timeline.remind(application: application, stage: stage, api: @api, now: now) }
    end

    test "schedule enqueues three reminders and the auto-reject at exact timestamps" do
      application = create_application

      assert_enqueued_jobs 4 do
        Timeline.schedule(application)
      end

      reminders = enqueued_jobs.select { |j| j["job_class"] == "ApplicationReminderJob" }
      assert_equal [ application.created_at + 24.hours,
                     application.created_at + 3.days,
                     application.created_at + 6.days ].map(&:to_f),
                   reminders.map { |j| j["scheduled_at"].to_time.to_f }

      reject = enqueued_jobs.find { |j| j["job_class"] == "ApplicationAutoRejectJob" }
      assert_in_delta (application.created_at + 7.days).to_f, reject["scheduled_at"].to_time.to_f, 1
    end

    test "a due reminder posts in the review channel, pings officers, and records the stage" do
      application = create_application(submitted_at: 25.hours.ago)

      remind(application, stage: 1, now: Time.current)

      assert_equal 1, @api.created.size
      assert_equal 1, application.reload.reminder_stage
      channel_id, payload = @api.created.first
      assert_equal CHANNEL, channel_id
      assert_includes payload["content"], "still waiting for review"
      assert_equal [ OFFICER_ROLE.to_s ], payload["allowed_mentions"]["roles"]
      assert_equal MESSAGE.to_s, payload.dig("message_reference", "message_id")
    end

    test "short-circuits when already sent, when a later stage is due, or when decided" do
      application = create_application(submitted_at: 25.hours.ago, reminder_stage: 1)
      remind(application, stage: 1, now: Time.current) # already sent
      assert_empty @api.created

      late = create_application(submitted_at: 6.days.ago - 1.hour)
      remind(late, stage: 1, now: Time.current) # stages 1-3 fire together after downtime
      remind(late, stage: 2, now: Time.current)
      assert_empty @api.created
      remind(late, stage: 3, now: Time.current) # only the latest due stage sends
      assert_equal 1, @api.created.size
      assert_equal 3, late.reload.reminder_stage

      decided = create_application(submitted_at: 25.hours.ago)
      with_tenant { decided.update!(status: :accepted, decided_at: Time.current) }
      remind(decided, stage: 1, now: Time.current)
      assert_equal 1, @api.created.size # unchanged
    end

    test "a transient send failure leaves the stage unrecorded so the job retry resends" do
      application = create_application(submitted_at: 25.hours.ago)
      @api.create_error = Discord::BotApi::Error.new("HTTP 500")

      assert_raises(Discord::BotApi::Error) { remind(application, stage: 1, now: Time.current) }
      assert_equal 0, application.reload.reminder_stage
    end

    test "a deleted channel is swallowed and the stage still advances" do
      application = create_application(submitted_at: 25.hours.ago)
      @api.create_error = Discord::BotApi::NotFound.new("gone")

      remind(application, stage: 1, now: Time.current)
      assert_equal 1, application.reload.reminder_stage
    end

    test "auto-reject rejects, repaints the review message, archives the membership" do
      application = create_application(submitted_at: 8.days.ago)

      with_tenant { Timeline.auto_reject(application: application, api: @api) }

      application.reload
      assert application.rejected?
      assert_nil application.decided_by_discord_id
      with_tenant { assert application.team_membership.reload.archived? }

      assert_equal 1, @api.edited.size
      _, message_id, payload = @api.edited.first
      assert_equal MESSAGE, message_id
      assert_includes payload["embeds"].first[:title], "Rejected"

      assert_equal 1, @api.created.size
      assert_includes @api.created.first.last["content"], "automatically rejected"
      assert_empty @api.created.first.last["allowed_mentions"]["roles"]
    end

    test "auto-reject is a no-op when an officer already decided" do
      application = create_application(submitted_at: 8.days.ago)
      with_tenant { Decide.call(application: application, decision: :accept, decided_by_discord_id: 99) }

      with_tenant { Timeline.auto_reject(application: application, api: @api) }

      assert application.reload.accepted?
      assert_empty @api.created
      assert_empty @api.edited
    end
  end
end
