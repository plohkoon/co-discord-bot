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

  # --- the shared REST post (modal and web submissions both go through it) ---

  class FakeApi
    attr_reader :created, :edited

    def initialize
      @created = []
      @edited = []
    end

    def create_message(channel_id, payload)
      @created << [ channel_id, payload ]
      { "id" => "424242" }
    end

    def edit_message(channel_id, message_id, payload)
      @edited << [ channel_id, message_id, payload ]
      {}
    end
  end

  test "post sends the officer ping + embed + buttons over REST and stores the ids" do
    subject = application
    api = FakeApi.new

    CoBot::ReviewMessage.post(team: subject.team, application: subject, api: api)

    channel_id, payload = api.created.sole
    assert_equal subject.team.review_channel_id, channel_id
    assert_includes payload["content"], "<@&#{subject.team.officer_role_id}>"
    assert_includes payload["embeds"].sole[:title], "Application — Alpha"
    ids = payload["components"].flat_map { |row| row[:components] }.map { |c| c[:custom_id] }
    assert_includes ids, "decide:accept:#{subject.id}"
    assert_includes ids, "decide:reject:#{subject.id}"
    # Only the officer role may ping.
    assert_equal({ "parse" => [], "roles" => [ subject.team.officer_role_id.to_s ] }, payload["allowed_mentions"])

    subject.reload
    assert_equal subject.team.review_channel_id, subject.review_channel_id
    assert_equal 424242, subject.review_message_id
  end

  test "a decide-time repaint reaches the message post stored, wherever it came from" do
    subject = application
    api = FakeApi.new
    CoBot::ReviewMessage.post(team: subject.team, application: subject, api: api)

    ActsAsTenant.with_tenant(guild) do
      subject.reload.update!(status: :accepted, decided_at: Time.current, decided_by_discord_id: 99)
      Applications::RefreshReviewMessage.call(subject, api: api)
    end

    channel_id, message_id, payload = api.edited.sole
    assert_equal subject.review_channel_id, channel_id
    assert_equal 424242, message_id
    assert_includes payload["embeds"].sole[:title], "Accepted"
  end
end
