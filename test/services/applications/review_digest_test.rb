require "test_helper"

module Applications
  class ReviewDigestTest < ActiveSupport::TestCase
    OFFICER_ROLE = 42
    CHANNEL = 900

    # Records every REST call; can simulate failures and a channel history.
    class FakeApi
      attr_reader :created, :edited
      attr_accessor :create_error, :newest_id

      def initialize
        @created = []
        @edited = []
        @next_id = 1_000
      end

      def create_message(channel_id, payload)
        raise create_error if create_error

        @created << [ channel_id, payload ]
        { "id" => (@next_id += 1).to_s }
      end

      def edit_message(channel_id, message_id, payload) = @edited << [ channel_id, message_id, payload ]

      def channel_messages(_channel_id, limit: 1) = newest_id ? [ { "id" => newest_id.to_s } ] : []
    end

    def guild = @guild ||= Guild.sync_from_discord(id: 1, name: "Test")

    def with_tenant(&block) = ActsAsTenant.with_tenant(guild, &block)

    def setup
      @api = FakeApi.new
      @team = with_tenant do
        Team.create!(name: "Alpha", team_role_id: 5, officer_role_id: OFFICER_ROLE, review_channel_id: CHANNEL)
      end
    end

    def apply(waiting:, username: "alice", user_id: nil, **attrs)
      user_id ||= rand(1_000_000)
      with_tenant do
        membership = TeamMembership.create!(team: @team, discord_user_id: user_id,
                                            discord_username: username, status: :pending)
        membership.team_applications.create!(team: @team, discord_user_id: user_id, discord_username: username,
                                             source: :applied, review_channel_id: CHANNEL,
                                             review_message_id: 901, created_at: waiting.ago, **attrs)
      end
    end

    def deliver(on: Date.current, now: Time.current)
      with_tenant { ReviewDigest.deliver(team: @team.reload, on: on, api: @api, now: now) }
    end

    def content = @api.created.first&.last&.fetch("content")

    test "one grouped message lists everything still waiting, with ages" do
      apply(waiting: 2.days, username: "alice")
      apply(waiting: 4.days, username: "bob")

      assert deliver

      assert_equal 1, @api.created.size, "one message, not one per application"
      assert_equal CHANNEL, @api.created.first.first
      assert_includes content, "2 applications waiting"
      assert_includes content, "(`alice`) — waiting 2 days"
      assert_includes content, "(`bob`) — waiting 4 days"
      assert content.index("`bob`") < content.index("`alice`"), "oldest first"
      assert_includes content, "<@&#{OFFICER_ROLE}>"
      assert_equal [ OFFICER_ROLE.to_s ], @api.created.first.last["allowed_mentions"]["roles"]
    end

    test "applications younger than the team's threshold are left out" do
      apply(waiting: 2.hours) # arrived today — the review message already said so
      apply(waiting: 3.days, username: "bob")

      deliver

      assert_includes content, "1 application waiting"
      assert_includes content, "`bob`"
      assert_not_includes content, "waiting 0 days"
    end

    test "a threshold of 0 lists everything, however new" do
      with_tenant { @team.update!(review_digest_after_days: 0) }
      apply(waiting: 2.hours)

      deliver

      assert_includes content, "1 application waiting"
    end

    test "nothing waiting means no message at all" do
      assert deliver

      assert_empty @api.created
      assert_equal Date.current, @team.reload.last_review_digest_on
    end

    test "paused applications are invisible to the digest and to the deadline" do
      application = apply(waiting: 9.days)
      with_tenant { Pause.pause(application: application, actor_discord_id: 7) }

      deliver

      assert_empty @api.created
      assert application.reload.pending?, "a parked application never expires"
    end

    test "the ping toggle keeps the mention but drops the notification" do
      with_tenant { @team.update!(remind_ping: false) }
      apply(waiting: 2.days)

      deliver

      assert_includes content, "<@&#{OFFICER_ROLE}>"
      assert_empty @api.created.first.last["allowed_mentions"]["roles"]
    end

    test "with the digest off nothing posts, but the 7-day sweep still runs" do
      with_tenant { @team.update!(review_digest: false) }
      expired = apply(waiting: 8.days)

      deliver

      assert_empty @api.created
      assert expired.reload.rejected?
      assert_nil expired.decided_by_discord_id, "a system decision, like the old auto-reject job"
    end

    test "overdue applications are retired, reported, and their review message repainted" do
      expired = apply(waiting: 8.days, username: "stale")
      apply(waiting: 2.days, username: "alice")

      deliver

      assert expired.reload.rejected?
      with_tenant { assert expired.team_membership.reload.archived? }
      assert_includes content, "1 application auto-rejected"
      assert_includes content, "`alice`"
      assert_not_includes content, "`stale`", "a retired application isn't also listed as waiting"

      assert_equal 1, @api.edited.size
      assert_includes @api.edited.first.last["embeds"].first[:title], "Rejected"
    end

    test "running twice in a day is a no-op the second time" do
      apply(waiting: 2.days)

      assert deliver
      assert_not deliver, "already done today"
      assert_equal 1, @api.created.size
    end

    test "no second digest while the last one is still the newest message" do
      apply(waiting: 2.days)
      deliver
      posted_id = @team.reload.last_review_digest_message_id
      assert posted_id

      # Next morning, nobody has said anything since.
      @api.newest_id = posted_id
      deliver(on: Date.current + 1)
      assert_equal 1, @api.created.size

      # The morning after, someone has (a new review message, say).
      @api.newest_id = 999_999
      deliver(on: Date.current + 2)
      assert_equal 2, @api.created.size
    end

    test "a failed post leaves the day unstamped so the retry re-runs it" do
      apply(waiting: 2.days)
      @api.create_error = Discord::BotApi::Error.new("HTTP 500")

      assert_raises(Discord::BotApi::Error) { deliver }
      assert_nil @team.reload.last_review_digest_on

      @api.create_error = nil
      assert deliver
      assert_equal 1, @api.created.size
    end

    test "a retry after a failed post still reports the applications it retired" do
      apply(waiting: 8.days)
      @api.create_error = Discord::BotApi::Error.new("HTTP 500")
      assert_raises(Discord::BotApi::Error) { deliver }

      @api.create_error = nil
      deliver

      # The rejection committed on the first pass; the retry re-reads it from
      # the row rather than from memory, so the digest still mentions it.
      assert_includes content, "1 application auto-rejected"
    end

    test "a role-removal archive isn't reported as a 7-day expiry" do
      # Memberships::Archive also decides with decided_by_discord_id: nil, so
      # "the system rejected it" alone can't mean "it timed out".
      pulled = apply(waiting: 1.day, username: "left")
      with_tenant { Memberships::Archive.call(pulled.team_membership) }
      apply(waiting: 3.days, username: "alice")

      deliver

      assert pulled.reload.rejected?
      assert_not_includes content, "auto-rejected"
      assert_includes content, "`alice`"
    end

    test "a deleted channel doesn't wedge the sweep" do
      apply(waiting: 2.days)
      @api.create_error = Discord::BotApi::NotFound.new("gone")

      assert deliver
      assert_equal Date.current, @team.reload.last_review_digest_on
    end

    test "the deadline runs from the resume, not the original submission" do
      application = apply(waiting: 9.days)
      with_tenant { Pause.pause(application: application, actor_discord_id: 7) }
      with_tenant { Pause.resume(application: application) }

      deliver

      assert application.reload.pending?, "the restarted clock has six days left"
      assert_empty @api.created, "and it's too new to list"
    end
  end
end
