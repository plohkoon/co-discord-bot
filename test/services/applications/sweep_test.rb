require "test_helper"

module Applications
  class SweepTest < ActiveSupport::TestCase
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

    def create_application(submitted_at:, reminder_stage: 0)
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

    def sweep(now: Time.current)
      with_tenant { Sweep.new(api: @api, now: now).call }
    end

    test "no reminder before 24 hours" do
      create_application(submitted_at: 23.hours.ago)
      sweep
      assert_empty @api.created
    end

    test "reminds at each threshold exactly once, pinging officers" do
      application = create_application(submitted_at: 25.hours.ago)

      sweep
      assert_equal 1, @api.created.size
      assert_equal 1, application.reload.reminder_stage
      channel_id, payload = @api.created.first
      assert_equal CHANNEL, channel_id
      assert_includes payload["content"], "still waiting for review"
      assert_equal [ OFFICER_ROLE.to_s ], payload["allowed_mentions"]["roles"]
      assert_equal MESSAGE.to_s, payload.dig("message_reference", "message_id")

      sweep # same age band — nothing new
      assert_equal 1, @api.created.size

      sweep(now: application.created_at + 3.days + 1.hour)
      assert_equal 2, @api.created.size
      assert_equal 2, application.reload.reminder_stage

      sweep(now: application.created_at + 6.days + 1.hour)
      assert_equal 3, @api.created.size
      assert_equal 3, application.reload.reminder_stage
    end

    test "skipped thresholds collapse into a single catch-up reminder" do
      application = create_application(submitted_at: 6.days.ago - 1.hour)
      sweep
      assert_equal 1, @api.created.size
      assert_equal 3, application.reload.reminder_stage
    end

    test "a failed reminder is retried on the next sweep" do
      application = create_application(submitted_at: 25.hours.ago)
      @api.create_error = Discord::BotApi::Error.new("HTTP 500")

      sweep
      assert_equal 0, application.reload.reminder_stage

      @api.create_error = nil
      sweep
      assert_equal 1, application.reload.reminder_stage
    end

    test "auto-rejects after 7 days, repaints the review message, archives the membership" do
      application = create_application(submitted_at: 8.days.ago)

      sweep

      application.reload
      assert application.rejected?
      assert_nil application.decided_by_discord_id
      assert application.decided_at.present?
      with_tenant { assert application.team_membership.reload.archived? }

      assert_equal 1, @api.edited.size
      _, message_id, payload = @api.edited.first
      assert_equal MESSAGE, message_id
      assert_includes payload["embeds"].first[:title], "Rejected"

      assert_equal 1, @api.created.size
      assert_includes @api.created.first.last["content"], "automatically rejected"
      assert_empty @api.created.first.last["allowed_mentions"]["roles"]
    end

    test "decided applications are left alone" do
      application = create_application(submitted_at: 8.days.ago)
      with_tenant { application.update!(status: :accepted, decided_at: Time.current) }

      sweep
      assert_empty @api.created
      assert_empty @api.edited
    end
  end
end
