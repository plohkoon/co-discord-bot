require "test_helper"

# The hourly sweep only does a guild's work when that GUILD's clock reaches the
# digest hour — a single daily UTC cron would fire mid-afternoon in half the
# servers we run in.
class ReviewDigestSweepJobTest < ActiveSupport::TestCase
  HOUR = ReviewDigestSweepJob::DIGEST_HOUR

  class FakeApi
    attr_reader :created

    def initialize = @created = []

    def create_message(channel_id, payload)
      @created << [ channel_id, payload ]
      { "id" => "1" }
    end

    def edit_message(*) = nil
    def channel_messages(*, **) = []
  end

  def setup
    @api = FakeApi.new
  end

  def create_guild(id:, name:, time_zone:)
    Guild.sync_from_discord(id: id, name: name).tap { |guild| guild.update!(time_zone: time_zone) }
  end

  # A team with one application old enough to be listed.
  def seed_team(guild, name)
    ActsAsTenant.with_tenant(guild) do
      team = Team.create!(name: name, team_role_id: 5, officer_role_id: 6, review_channel_id: 7)
      membership = TeamMembership.create!(team: team, discord_user_id: rand(1_000_000),
                                          discord_username: "alice", status: :pending)
      membership.team_applications.create!(team: team, discord_user_id: membership.discord_user_id,
                                           discord_username: "alice", source: :applied,
                                           created_at: 3.days.ago)
      team
    end
  end

  def run_at(utc) = ReviewDigestSweepJob.new.perform(now: utc, api: @api)

  test "each guild is judged against its own clock and stamped with its own date" do
    tokyo = create_guild(id: 11, name: "Tokyo", time_zone: "Asia/Tokyo")
    denver = create_guild(id: 22, name: "Denver", time_zone: "America/Denver")
    seed_team(tokyo, "Tokyo Raiders")
    seed_team(denver, "Denver Raiders")

    # Midnight in Denver is mid-afternoon in Tokyo: one guild is past its digest
    # hour, the other hasn't reached it. Derived from the zones rather than
    # hardcoded so DST can't drift the premise.
    moment = ActiveSupport::TimeZone["America/Denver"].now.beginning_of_day.utc
    assert_operator moment.in_time_zone(tokyo.tz).hour, :>=, HOUR
    assert_operator moment.in_time_zone(denver.tz).hour, :<, HOUR

    run_at(moment)

    assert_equal 1, @api.created.size
    assert_includes @api.created.first.last["content"], "Tokyo Raiders"
    # Stamped with the TOKYO-local date, which isn't Denver's date at all.
    assert_equal moment.in_time_zone(tokyo.tz).to_date, tokyo.teams.first.reload.last_review_digest_on
    assert_nil ActsAsTenant.with_tenant(denver) { Team.first.last_review_digest_on }

    # Denver's turn comes round when Denver's own morning arrives.
    run_at(ActiveSupport::TimeZone["America/Denver"].now.change(hour: HOUR).utc)
    assert_equal 2, @api.created.size
    assert_includes @api.created.last.last["content"], "Denver Raiders"
  end

  test "a run before the guild's digest hour does nothing" do
    guild = create_guild(id: 33, name: "Guild", time_zone: "UTC")
    seed_team(guild, "Raiders")

    run_at(Time.current.utc.change(hour: HOUR - 1))

    assert_empty @api.created
  end

  test "a run after the digest hour still catches the day up" do
    # The scheduler missing its slot (worker restart, backlog) must not cost the
    # guild its digest until tomorrow.
    guild = create_guild(id: 66, name: "Guild", time_zone: "UTC")
    seed_team(guild, "Raiders")

    run_at(Time.current.utc.change(hour: HOUR + 4))

    assert_equal 1, @api.created.size
  end

  test "an hourly re-run inside the same local hour doesn't post twice" do
    guild = create_guild(id: 44, name: "Guild", time_zone: "UTC")
    seed_team(guild, "Raiders")

    moment = Time.current.utc.change(hour: HOUR)
    run_at(moment)
    run_at(moment + 20.minutes) # a retry, or the scheduler firing again

    assert_equal 1, @api.created.size
  end

  test "guilds the bot was removed from are skipped" do
    guild = create_guild(id: 55, name: "Gone", time_zone: "UTC")
    seed_team(guild, "Raiders")
    guild.update!(removed_at: Time.current)

    run_at(Time.current.utc.change(hour: HOUR))

    assert_empty @api.created
  end
end
