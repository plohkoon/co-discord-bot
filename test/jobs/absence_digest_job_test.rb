require "test_helper"

class AbsenceDigestJobTest < ActiveSupport::TestCase
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

  CHANNEL = 700
  DAY = Date.new(2026, 7, 26)

  def guild = @guild ||= Guild.sync_from_discord(id: 1, name: "Test")

  def team
    @team ||= ActsAsTenant.with_tenant(guild) do
      Team.create!(name: "Alpha", team_role_id: 5, officer_role_id: 6, review_channel_id: CHANNEL)
    end
  end

  def digest_with_absence
    ActsAsTenant.with_tenant(guild) do
      Absence.create!(team: team, discord_user_id: 11, discord_username: "alice",
                      absence_on: DAY, created_by_discord_id: 11)
      AbsenceDigest.create!(team: team, digest_on: DAY)
    end
  end

  def setup = @api = FakeApi.new

  test "delivers the digest to the notify channel and marks it sent" do
    digest = digest_with_absence

    AbsenceDigestJob.perform_now(guild_id: guild.id, digest_id: digest.id, api: @api)

    assert_equal 1, @api.created.size
    assert_equal CHANNEL, @api.created.first.first
    assert digest.reload.sent?
  end

  test "a missing digest is a no-op" do
    AbsenceDigestJob.perform_now(guild_id: guild.id, digest_id: 0, api: @api)
    assert_empty @api.created
  end

  test "a missing guild is a no-op" do
    AbsenceDigestJob.perform_now(guild_id: 0, digest_id: 1, api: @api)
    assert_empty @api.created
  end
end
