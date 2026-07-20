require "test_helper"

class AbsenceDigest::TimelineTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  OFFICER_ROLE = 42
  CHANNEL = 700

  # Records posts; can simulate failures.
  class FakeApi
    attr_reader :created
    attr_accessor :create_error

    def initialize
      @created = []
    end

    def create_message(channel_id, payload)
      raise create_error if create_error

      @created << [ channel_id, payload ]
    end
  end

  def guild = @guild ||= Guild.sync_from_discord(id: 1, name: "Test")

  def team(**attrs)
    @team ||= ActsAsTenant.with_tenant(guild) do
      Team.create!(name: "Alpha", team_role_id: 5, officer_role_id: OFFICER_ROLE, review_channel_id: CHANNEL, **attrs)
    end
  end

  def setup
    @api = FakeApi.new
  end

  def set_zone(name) = guild.update!(time_zone: name)

  def digest_for(date)
    ActsAsTenant.with_tenant(guild) { AbsenceDigest.create!(team: team, digest_on: date) }
  end

  def absence(user_id, on:, note: nil, status: :active, username: "u#{user_id}")
    ActsAsTenant.with_tenant(guild) do
      Absence.create!(team: team, discord_user_id: user_id, discord_username: username, absence_on: on,
                      note: note, created_by_discord_id: user_id, status: status)
    end
  end

  def deliver(digest, now: Time.current)
    ActsAsTenant.with_tenant(guild) { AbsenceDigest::Timeline.deliver(digest: digest, api: @api, now: now) }
  end

  test "schedule fires at the guild-local DIGEST_HOUR" do
    set_zone("America/Chicago")
    digest = digest_for(Date.new(2026, 7, 26))

    assert_enqueued_jobs 1, only: AbsenceDigestJob do
      AbsenceDigest::Timeline.schedule(digest)
    end
    job = enqueued_jobs.find { |j| j["job_class"] == "AbsenceDigestJob" }
    fire = job["scheduled_at"].to_time
    assert_equal 8, fire.in_time_zone("America/Chicago").hour
    assert_equal Date.new(2026, 7, 26), fire.in_time_zone("America/Chicago").to_date
  end

  test "schedule stays at local 08:00 across a DST boundary" do
    set_zone("America/New_York")
    # 2026-03-08 is the US spring-forward day; the morning after is 2026-03-09.
    digest = digest_for(Date.new(2026, 3, 9))

    AbsenceDigest::Timeline.schedule(digest)

    job = enqueued_jobs.find { |j| j["job_class"] == "AbsenceDigestJob" }
    local = job["scheduled_at"].to_time.in_time_zone("America/New_York")
    assert_equal 8, local.hour # still local 8am, not 7 or 9
    assert_equal Date.new(2026, 3, 9), local.to_date
  end

  test "deliver groups the day's active call-outs into one message and pings only the officer role" do
    day = Date.new(2026, 7, 26)
    absence(11, on: day, username: "alice")
    absence(22, on: day, note: "back Monday", username: "bob")
    digest = digest_for(day)

    deliver(digest)

    assert_equal 1, @api.created.size
    channel_id, payload = @api.created.first
    assert_equal CHANNEL, channel_id
    assert_includes payload["content"], "<@&#{OFFICER_ROLE}>" # actually pings the leads
    assert_includes payload["content"], "Absences today for **Alpha**"
    assert_includes payload["content"], "<@11>"
    assert_includes payload["content"], "<@22> — back Monday"
    assert_empty payload["allowed_mentions"]["parse"]
    assert_equal [ OFFICER_ROLE.to_s ], payload["allowed_mentions"]["roles"]
    assert digest.reload.sent?
    assert_not_nil digest.sent_at
  end

  test "deliver posts to the lead channel when the team has one" do
    team(lead_channel_id: 999)
    day = Date.new(2026, 7, 26)
    absence(11, on: day)
    digest = digest_for(day)

    deliver(digest)

    assert_equal 999, @api.created.first.first
  end

  test "deliver excludes cancelled call-outs" do
    day = Date.new(2026, 7, 26)
    absence(11, on: day, username: "alice")
    absence(22, on: day, status: :cancelled, username: "bob")
    digest = digest_for(day)

    deliver(digest)

    content = @api.created.first.last["content"]
    assert_includes content, "<@11>"
    assert_not_includes content, "<@22>"
  end

  test "deliver marks sent with no message when nobody is out" do
    day = Date.new(2026, 7, 26)
    absence(11, on: day, status: :cancelled) # only a cancelled one
    digest = digest_for(day)

    deliver(digest)

    assert_empty @api.created
    assert digest.reload.sent?
  end

  test "deliver is idempotent — a re-fire after sent posts nothing" do
    day = Date.new(2026, 7, 26)
    absence(11, on: day)
    digest = digest_for(day)

    deliver(digest)
    deliver(digest.reload)

    assert_equal 1, @api.created.size
  end

  test "a transient send failure leaves the digest pending so the job retries" do
    day = Date.new(2026, 7, 26)
    absence(11, on: day)
    digest = digest_for(day)
    @api.create_error = Discord::BotApi::Error.new("HTTP 500")

    assert_raises(Discord::BotApi::Error) { deliver(digest) }
    assert digest.reload.pending?
  end

  test "a vanished channel is swallowed and the digest is still marked sent" do
    day = Date.new(2026, 7, 26)
    absence(11, on: day)
    digest = digest_for(day)
    @api.create_error = Discord::BotApi::NotFound.new("gone")

    deliver(digest)

    assert digest.reload.sent?
  end
end
