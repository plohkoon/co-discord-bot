require "test_helper"

# Cancelling a call-out from the web: a lead cancels any on their team, a raider
# cancels their own (the Discord-only self-service path), everyone else is blocked.
class AbsencesTest < ActionDispatch::IntegrationTest
  setup do
    @guild = Guild.create!(id: 555_000_111_222_333_444, name: "Raid Server")
    ActsAsTenant.with_tenant(@guild) do
      @team = Team.create!(name: "Alpha", team_role_id: 1, officer_role_id: 2, review_channel_id: 3)
    end
  end

  def make_lead!(user)
    ActsAsTenant.with_tenant(@guild) do
      TeamOfficer.create!(team: @team, discord_user_id: user.discord_id, discord_username: user.username)
    end
  end

  def make_absence(discord_user_id:)
    ActsAsTenant.with_tenant(@guild) do
      Absence.create!(team: @team, discord_user_id: discord_user_id, discord_username: "someone",
                      absence_on: Date.current + 3, created_by_discord_id: discord_user_id)
    end
  end

  test "a team lead can cancel any call-out on their team" do
    make_lead!(users(:member))
    absence = make_absence(discord_user_id: 999) # someone else's
    sign_in_as users(:member), member: [ @guild ]

    delete guild_absence_path(@guild, absence)

    assert_redirected_to guild_path(@guild)
    assert absence.reload.cancelled?
    assert_equal users(:member).discord_id, absence.cancelled_by_discord_id
  end

  test "a raider can cancel their own call-out" do
    absence = make_absence(discord_user_id: users(:member).discord_id)
    sign_in_as users(:member), member: [ @guild ]

    delete guild_absence_path(@guild, absence)

    assert_redirected_to guild_path(@guild)
    assert absence.reload.cancelled?
  end

  test "an unrelated member cannot cancel someone else's call-out" do
    absence = make_absence(discord_user_id: 999)
    sign_in_as users(:member), member: [ @guild ]

    delete guild_absence_path(@guild, absence)

    assert_redirected_to guild_path(@guild)
    assert absence.reload.active? # nothing was cancelled
  end

  test "a manager can cancel any call-out" do
    absence = make_absence(discord_user_id: 999)
    sign_in_as users(:member), manageable: [ @guild ]

    delete guild_absence_path(@guild, absence)

    assert absence.reload.cancelled?
  end
end
