require "test_helper"

class TeamTest < ActiveSupport::TestCase
  def guild = @guild ||= Guild.sync_from_discord(id: 1, name: "Test")

  def team(**attrs)
    ActsAsTenant.with_tenant(guild) do
      Team.create!(name: "Alpha", team_role_id: 5, officer_role_id: 6, review_channel_id: 7, **attrs)
    end
  end

  test "resolved_apply_response falls back to the default with tokens substituted" do
    message = team.resolved_apply_response(user_mention: "<@11>")

    assert_includes message, "Alpha"          # {team}
    assert_includes message, "<@11>"           # {user}
    assert_not_includes message, "{team}"
    assert_not_includes message, "{user}"
  end

  test "resolved_absence_response falls back to the default with tokens substituted" do
    message = team.resolved_absence_response(user_mention: "<@22>")

    assert_includes message, "Alpha"
    assert_includes message, "<@22>"
    assert_not_includes message, "{team}"
    assert_not_includes message, "{user}"
  end

  test "a stored template overrides the default and is substituted" do
    subject = team(apply_response: "Hey {user}, welcome to {team}.")

    assert_equal "Hey <@11>, welcome to Alpha.", subject.resolved_apply_response(user_mention: "<@11>")
  end

  test "a stored absence template overrides the default" do
    subject = team(absence_response: "{user} out for {team}, noted.")

    assert_equal "<@33> out for Alpha, noted.", subject.resolved_absence_response(user_mention: "<@33>")
  end

  test "a blank template is treated as unset and uses the default" do
    subject = team(apply_response: "")

    assert_equal Team::DEFAULT_APPLY_RESPONSE.gsub("{team}", "Alpha").gsub("{user}", "<@11>"),
                 subject.resolved_apply_response(user_mention: "<@11>")
  end

  test "notify_channel_id prefers the lead channel, falling back to the review channel" do
    assert_equal 7, Team.new(review_channel_id: 7).notify_channel_id                       # no lead channel
    assert_equal 99, Team.new(review_channel_id: 7, lead_channel_id: 99).notify_channel_id # lead channel wins
  end

  test "teams recruit by default" do
    assert team.recruiting?
  end

  test "resolved_closed_message falls back to the default" do
    assert_equal Team::DEFAULT_CLOSED_MESSAGE, team.resolved_closed_message
  end

  test "a stored closed_message overrides the default with {team} substituted" do
    subject = team(closed_message: "{team} is full — try again next season.")

    assert_equal "Alpha is full — try again next season.", subject.resolved_closed_message
  end

  test "a new team gets a pinging daily digest that skips same-day applications" do
    subject = team

    assert subject.review_digest?
    assert subject.remind_ping?
    assert_equal 1, subject.review_digest_after_days
  end

  test "the digest threshold has to be a day count the sweep can act on" do
    # Past 7 an application would auto-reject before it was ever listed.
    assert team(review_digest_after_days: 0).valid?
    assert team(name: "Beta", review_digest_after_days: 7).valid?

    subject = team(name: "Gamma")
    subject.review_digest_after_days = 8
    assert_not subject.valid?
    subject.review_digest_after_days = -1
    assert_not subject.valid?
  end
end
