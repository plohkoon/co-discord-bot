require "test_helper"

class AbsenceDigestTest < ActiveSupport::TestCase
  def guild = @guild ||= Guild.sync_from_discord(id: 1, name: "Test")

  def team
    @team ||= ActsAsTenant.with_tenant(guild) do
      Team.create!(name: "Alpha", team_role_id: 5, officer_role_id: 6, review_channel_id: 7)
    end
  end

  test "defaults to pending and belongs to a team + guild" do
    digest = ActsAsTenant.with_tenant(guild) do
      AbsenceDigest.create!(team: team, digest_on: Date.new(2026, 7, 26))
    end

    assert digest.pending?
    assert_equal team, digest.team
    assert_equal guild.id, digest.guild_id # auto-filled by the tenant
  end

  test "one digest per team per day (unique index)" do
    ActsAsTenant.with_tenant(guild) do
      AbsenceDigest.create!(team: team, digest_on: Date.new(2026, 7, 26))
      assert_raises(ActiveRecord::RecordNotUnique) do
        AbsenceDigest.create!(team: team, digest_on: Date.new(2026, 7, 26))
      end
    end
  end
end
