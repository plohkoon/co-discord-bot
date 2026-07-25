require "test_helper"

# Each notable event fires GuildLog.record at exactly one shared service seam.
# These tests assert the seam enqueues a GuildLogJob at the right severity; the
# job's own posting behaviour is covered in GuildLogJobTest.
class GuildLogSeamsTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  FakeUser = Struct.new(:id, :username)

  class FakeEvent
    attr_reader :user
    def initialize(user_id) = @user = FakeUser.new(user_id, "alice")
    def value(_key) = "an answer"
  end

  # Swallows the review-message repaint / notice so auto-reject does no network.
  class FakeApi
    def create_message(*) = nil
    def edit_message(*) = nil
  end

  # A guild with a single log channel: every level collapses onto it, so any
  # seam that fires will enqueue.
  def guild = @guild ||= Guild.create!(id: 1, name: "Test", log_channel_id: 900)

  def team
    @team ||= ActsAsTenant.with_tenant(guild) do
      Team.create!(name: "Alpha", team_role_id: 5, officer_role_id: 6, review_channel_id: 7)
    end
  end

  def with_tenant(&block) = ActsAsTenant.with_tenant(guild, &block)

  # The severities of every GuildLogJob enqueued so far.
  def logged_levels
    guild_log_args.map { |args| args[:level] }
  end

  # Deserialized kwargs of every enqueued GuildLogJob.
  def guild_log_args
    enqueued_jobs.select { |j| j["job_class"] == "GuildLogJob" }
                 .map { |j| ActiveJob::Arguments.deserialize(j["arguments"]).first }
  end

  def pending_application(user_id: 11)
    with_tenant do
      membership = TeamMembership.create!(team: team, discord_user_id: user_id, discord_username: "alice", status: :pending)
      membership.team_applications.create!(team: team, discord_user_id: user_id, discord_username: "alice", source: :applied)
    end
  end

  test "submitting an application logs a HIGH event" do
    with_tenant { Applications::Submit.call(team: team, event: FakeEvent.new(11)) }

    assert_equal [ :high ], logged_levels
  end

  test "a human accept logs a LOW event, tagged with the decider" do
    application = pending_application

    with_tenant { Applications::Decide.call(application: application, decision: :accept, decided_by_discord_id: 99) }

    assert_equal [ :low ], logged_levels
    args = guild_log_args.last
    assert_equal 99, args[:actor_id]
    assert_equal "Application accepted", args[:title]
  end

  test "a human reject logs a LOW event" do
    application = pending_application

    with_tenant { Applications::Decide.call(application: application, decision: :reject, decided_by_discord_id: 99) }

    assert_equal [ :low ], logged_levels
  end

  test "the 7-day auto-reject logs a HIGH event with no actor" do
    # The deadline is swept by the daily digest now rather than a per-application
    # job, but it still goes through Decide with no decider — so it still logs
    # HIGH, and Archive's internal rejects still stay quiet (log_event: false).
    application = pending_application
    with_tenant { application.update!(created_at: 8.days.ago) }

    with_tenant { Applications::ReviewDigest.deliver(team: team, on: Date.current, api: FakeApi.new) }

    assert application.reload.rejected?
    assert_equal [ :high ], logged_levels
    assert_nil guild_log_args.last[:actor_id]
  end

  test "removing an active member logs a single LOW event" do
    membership = with_tenant do
      TeamMembership.create!(team: team, discord_user_id: 11, discord_username: "alice", status: :active)
    end

    with_tenant { Memberships::Archive.call(membership) }

    assert_equal [ :low ], logged_levels # no stray HIGH from an internal reject
  end

  test "a manual grant that resolves a pending application does not log a decision" do
    pending_application

    # Activate reconciles the pending app via Decide(log_event: false) — the
    # grant is not a review decision, so nothing is logged here.
    with_tenant { Memberships::Activate.call(team: team, discord_user_id: 11, username: "alice") }

    assert_empty logged_levels
  end

  test "re-archiving an already-archived membership does not re-log" do
    membership = with_tenant do
      TeamMembership.create!(team: team, discord_user_id: 11, discord_username: "alice", status: :archived, left_at: Time.current)
    end

    with_tenant { Memberships::Archive.call(membership) }

    assert_empty logged_levels
  end

  test "creating a team (TeamBackfillJob) logs a single LOW 'Team created' event" do
    t = team

    # Backfill pages the guild over REST; swap it out so the job exercises only
    # the log seam. The job also enqueues RosterRefreshJob, which we ignore here.
    original = Memberships::Backfill.method(:call)
    Memberships::Backfill.define_singleton_method(:call) { |**| 0 }
    begin
      TeamBackfillJob.perform_now(guild_id: guild.id, team_id: t.id)
    ensure
      Memberships::Backfill.define_singleton_method(:call, original)
    end

    created = guild_log_args.select { |args| args[:title] == "Team created" }
    assert_equal 1, created.size
    assert_equal :low, created.first[:level]
  end
end
