require "test_helper"

class AbsenceLeadNotifyJobTest < ActiveSupport::TestCase
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

  OFFICER_ROLE = 42
  REVIEW = 700
  LEAD = 800
  DAY = Date.new(2026, 7, 26)

  def guild = @guild ||= Guild.sync_from_discord(id: 1, name: "Test")

  def team(**attrs)
    @team ||= ActsAsTenant.with_tenant(guild) do
      Team.create!(name: "Alpha", team_role_id: 5, officer_role_id: OFFICER_ROLE, review_channel_id: REVIEW, **attrs)
    end
  end

  def absence(note: nil)
    ActsAsTenant.with_tenant(guild) do
      Absence.create!(team: team, discord_user_id: 11, discord_username: "alice",
                      absence_on: DAY, note: note, created_by_discord_id: 11)
    end
  end

  def setup = @api = FakeApi.new

  def run_job(absence_id) = AbsenceLeadNotifyJob.perform_now(guild_id: guild.id, absence_id: absence_id, api: @api)

  test "posts the heads-up to the notify channel with only the officer role pingable" do
    run_job(absence(note: "food poisoning").id)

    assert_equal 1, @api.created.size
    channel_id, payload = @api.created.first
    assert_equal REVIEW, channel_id # no lead channel -> review channel
    assert_includes payload["content"], "<@&#{OFFICER_ROLE}>" # actually pings the leads
    assert_includes payload["content"], "<@11> called out of **Alpha**"
    assert_includes payload["content"], "food poisoning"
    assert_includes payload["content"], "<t:" # a Discord timestamp for the day
    assert_empty payload["allowed_mentions"]["parse"]
    assert_equal [ OFFICER_ROLE.to_s ], payload["allowed_mentions"]["roles"]
  end

  test "posts to the lead channel when the team has one" do
    team(lead_channel_id: LEAD)
    run_job(absence.id)

    assert_equal LEAD, @api.created.first.first
  end

  test "swallows a vanished channel (NotFound)" do
    @api.create_error = Discord::BotApi::NotFound.new("gone")

    assert_nothing_raised { run_job(absence.id) }
    assert_empty @api.created
  end

  test "a missing absence is a no-op" do
    assert_nothing_raised { run_job(0) }
    assert_empty @api.created
  end
end
