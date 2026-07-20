require "test_helper"

class AbsenceTest < ActiveSupport::TestCase
  def guild = @guild ||= Guild.sync_from_discord(id: 1, name: "Test")

  def team
    @team ||= ActsAsTenant.with_tenant(guild) do
      Team.create!(name: "Alpha", team_role_id: 5, officer_role_id: 6, review_channel_id: 7)
    end
  end

  def create_absence(**attrs)
    ActsAsTenant.with_tenant(guild) do
      Absence.create!({ team: team, discord_user_id: 11, discord_username: "alice",
                        absence_on: Date.new(2026, 7, 26), created_by_discord_id: 11 }.merge(attrs))
    end
  end

  test "defaults to active and exposes a mention" do
    absence = create_absence
    assert absence.active?
    assert_equal "<@11>", absence.mention
  end

  test "requires absence_on and discord_user_id" do
    ActsAsTenant.with_tenant(guild) do
      absence = Absence.new(team: team, created_by_discord_id: 11)
      assert_not absence.valid?
      assert absence.errors[:absence_on].any?
      assert absence.errors[:discord_user_id].any?
    end
  end

  test "the partial-unique index blocks a second ACTIVE call-out for the same user/team/day" do
    create_absence
    assert_raises(ActiveRecord::RecordNotUnique) { create_absence }
  end

  test "a cancelled call-out frees the day for a fresh active one" do
    first = create_absence
    ActsAsTenant.with_tenant(guild) { first.update!(status: :cancelled, cancelled_at: Time.current) }

    assert_nothing_raised { create_absence }
  end

  test "scopes: active, upcoming, on, for_user" do
    today = Date.current
    ActsAsTenant.with_tenant(guild) do
      soon = create_absence(absence_on: today + 2)
      create_absence(discord_user_id: 22, absence_on: today - 3) # past
      cancelled = create_absence(discord_user_id: 33, absence_on: today + 5)
      cancelled.update!(status: :cancelled, cancelled_at: Time.current)

      assert_equal [ soon.id ], Absence.active.upcoming.pluck(:id)
      assert_equal [ soon.id ], Absence.on(today + 2).pluck(:id)
      assert_equal [ soon.id ], Absence.for_user(11).where("absence_on >= ?", today).pluck(:id)
    end
  end

  test "upcoming floors on the guild's local today, not the app's UTC" do
    ActsAsTenant.with_tenant(guild) { guild.update!(time_zone: "Hawaii") } # UTC-10

    # 2026-07-26 05:00 UTC is still 2026-07-25 in Hawaii — a call-out for the
    # guild-local "today" must stay upcoming (UTC would have rolled to the 26th).
    travel_to Time.utc(2026, 7, 26, 5, 0) do
      todays = create_absence(absence_on: Date.new(2026, 7, 25))
      ActsAsTenant.with_tenant(guild) do
        assert_includes Absence.active.upcoming.pluck(:id), todays.id
      end
    end
  end
end
