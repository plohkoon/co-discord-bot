require "test_helper"

class ConfirmationDmJobTest < ActiveSupport::TestCase
  def guild = @guild ||= Guild.sync_from_discord(id: 1, name: "Test")

  def team(**attrs)
    @team ||= ActsAsTenant.with_tenant(guild) do
      Team.create!(name: "Alpha", team_role_id: 5, officer_role_id: 6, review_channel_id: 7, **attrs)
    end
  end

  def run_job(kind:, team_id: team.id, discord_user_id: 42)
    ConfirmationDmJob.perform_now(guild_id: guild.id, team_id: team_id, discord_user_id: discord_user_id, kind: kind)
  end

  # DirectMessage.call has no api arg here, so we stub the service itself.
  def stub_direct_message(handler)
    original = Notifications::DirectMessage.method(:call)
    Notifications::DirectMessage.define_singleton_method(:call) { |**kwargs| handler.call(**kwargs) }
    yield
  ensure
    Notifications::DirectMessage.define_singleton_method(:call, original)
  end

  test "kind apply resolves the default template and DMs the applicant" do
    sent = []
    stub_direct_message(->(**kwargs) { sent << kwargs }) { run_job(kind: "apply") }

    assert_equal 1, sent.size
    assert_equal 42, sent.first[:user_id]
    assert_includes sent.first[:content], "Alpha"  # {team}
    assert_includes sent.first[:content], "<@42>"  # {user}
  end

  test "kind apply uses the team's custom template" do
    team(apply_response: "Yo {user} — {team} got it.")

    sent = []
    stub_direct_message(->(**kwargs) { sent << kwargs }) { run_job(kind: "apply") }

    assert_equal "Yo <@42> — Alpha got it.", sent.first[:content]
  end

  test "an unknown kind sends nothing" do
    sent = []
    stub_direct_message(->(**kwargs) { sent << kwargs }) { run_job(kind: "bogus") }

    assert_empty sent
  end

  test "a missing team sends nothing" do
    sent = []
    stub_direct_message(->(**kwargs) { sent << kwargs }) { run_job(kind: "apply", team_id: 0) }

    assert_empty sent
  end

  test "a team from another guild is invisible in this tenant — sends nothing" do
    other = Guild.sync_from_discord(id: 2, name: "Other")
    other_team = ActsAsTenant.with_tenant(other) do
      Team.create!(name: "Beta", team_role_id: 9, officer_role_id: 10, review_channel_id: 11)
    end

    sent = []
    stub_direct_message(->(**kwargs) { sent << kwargs }) { run_job(kind: "apply", team_id: other_team.id) }

    assert_empty sent
  end
end
