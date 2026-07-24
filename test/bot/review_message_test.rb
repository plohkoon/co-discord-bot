require "test_helper"

# The officer review message's live (pending/paused) face — the decided face is
# covered through Applications::Timeline's auto-reject test.
class ReviewMessageTest < ActiveSupport::TestCase
  def guild = @guild ||= Guild.sync_from_discord(id: 1, name: "Test")

  def application(**attrs)
    ActsAsTenant.with_tenant(guild) do
      team = Team.create!(name: "Alpha", team_role_id: 5, officer_role_id: 6, review_channel_id: 7)
      membership = TeamMembership.create!(team: team, discord_user_id: 11, discord_username: "alice", status: :pending)
      membership.team_applications.create!(team: team, discord_user_id: 11, discord_username: "alice",
                                           source: :applied, **attrs)
    end
  end

  # custom_ids of every button in the view, flattened across rows.
  def button_ids(view) = view.to_a.flat_map { |row| row[:components] }.map { |button| button[:custom_id] }

  def labels(view) = view.to_a.flat_map { |row| row[:components] }.map { |button| button[:label] }

  test "a live application offers Accept, Reject and Pause" do
    subject = application

    view = CoBot::ReviewMessage.decision_view(subject)

    assert_includes button_ids(view), "decide:accept:#{subject.id}"
    assert_includes button_ids(view), "decide:reject:#{subject.id}"
    assert_includes button_ids(view), "pause:pause:#{subject.id}"
    assert_not_includes button_ids(view), "pause:resume:#{subject.id}"
  end

  test "a paused application swaps Pause for Resume but keeps Accept and Reject" do
    subject = application(paused_at: Time.current, paused_by_discord_id: 99)

    view = CoBot::ReviewMessage.decision_view(subject)

    assert_includes button_ids(view), "pause:resume:#{subject.id}"
    assert_not_includes button_ids(view), "pause:pause:#{subject.id}"
    assert_includes labels(view), "Accept"
    assert_includes labels(view), "Reject"
  end

  test "the paused embed says who parked it and why nothing is happening" do
    subject = application(paused_at: Time.current, paused_by_discord_id: 99)

    embed = CoBot::ReviewMessage.pending_embed(subject.team, subject)

    assert_includes embed.title, "Paused"
    assert_includes embed.description, "<@99>"
    assert_includes embed.description, "auto-reject"
    assert_equal CoBot::ReviewMessage::PAUSED, embed.color
  end

  test "an unpaused application keeps the plain pending embed" do
    subject = application

    embed = CoBot::ReviewMessage.pending_embed(subject.team, subject)

    assert_not_includes embed.title, "Paused"
    assert_equal CoBot::ReviewMessage::BRAND, embed.color
  end
end
