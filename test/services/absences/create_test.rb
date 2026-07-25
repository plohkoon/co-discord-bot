require "test_helper"

module Absences
  class CreateTest < ActiveSupport::TestCase
    include ActiveJob::TestHelper

    FakeUser = Struct.new(:id, :username)

    # Stands in for the modal-submit event (Create reads the caller off it).
    class FakeEvent
      attr_reader :user

      def initialize(user_id, username = "alice")
        @user = FakeUser.new(user_id, username)
      end
    end

    DAY = Date.new(2026, 7, 26)

    def guild = @guild ||= Guild.sync_from_discord(id: 1, name: "Test")

    def team
      @team ||= ActsAsTenant.with_tenant(guild) do
        Team.create!(name: "Alpha", team_role_id: 5, officer_role_id: 6, review_channel_id: 7)
      end
    end

    def make_member(user_id, username: "alice", status: :active)
      ActsAsTenant.with_tenant(guild) do
        TeamMembership.create!(team: team, discord_user_id: user_id, discord_username: username, status: status)
      end
    end

    def create_for(user_id, username: "alice", note: nil, on: DAY)
      ActsAsTenant.with_tenant(guild) do
        Create.call(team: team, event: FakeEvent.new(user_id, username), absence_on: on, note: note)
      end
    end

    test "records the call-out linked to the caller's active membership" do
      membership = make_member(11)

      absence = create_for(11, note: "  flu  ")

      assert absence.active?
      assert_equal DAY, absence.absence_on
      assert_equal membership.id, absence.team_membership_id
      assert_equal 11, absence.created_by_discord_id
      assert_equal "flu", absence.note # stripped
      assert_equal guild.id, absence.guild_id
    end

    test "creates exactly one digest and schedules exactly one job even when a second person calls out for the same day" do
      make_member(11)
      make_member(22, username: "bob")

      assert_enqueued_jobs 1, only: AbsenceDigestJob do
        create_for(11)
        create_for(22, username: "bob")
      end

      ActsAsTenant.with_tenant(guild) do
        assert_equal 1, AbsenceDigest.where(team: team, digest_on: DAY).count
        assert_equal 2, Absence.on(DAY).active.count
      end
    end

    test "enqueues the lead heads-up and the kind:absence confirmation DM after commit" do
      make_member(11)

      assert_enqueued_with(job: AbsenceLeadNotifyJob) do
        assert_enqueued_with(
          job: ConfirmationDmJob,
          args: [ { guild_id: guild.id, team_id: team.id, discord_user_id: 11, kind: "absence" } ]
        ) { create_for(11) }
      end
    end

    test "the digest job is scheduled for the guild-local morning of the day" do
      make_member(11)
      create_for(11)

      job = enqueued_jobs.find { |j| j["job_class"] == "AbsenceDigestJob" }
      expected = DAY.in_time_zone(guild.tz).change(hour: AbsenceDigest::Timeline::DIGEST_HOUR)
      assert_in_delta expected.to_f, job["scheduled_at"].to_time.to_f, 1
    end

    test "a second active call-out for the same user/team/day raises DuplicateAbsence" do
      make_member(11)
      create_for(11)

      assert_raises(Create::DuplicateAbsence) { create_for(11) }
      ActsAsTenant.with_tenant(guild) { assert_equal 1, Absence.on(DAY).count }
    end

    test "a caller without an active membership raises NotOnTeam" do
      make_member(11, status: :pending)

      assert_raises(Create::NotOnTeam) { create_for(11) }
      assert_no_enqueued_jobs
      ActsAsTenant.with_tenant(guild) { assert_equal 0, Absence.count }
    end
  end
end
