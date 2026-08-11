require "test_helper"

module Discord
  class GuildMembershipTest < ActiveSupport::TestCase
    # Stands in for Discord::BotApi's member lookup.
    class FakeApi
      def initialize(member: nil, error: nil, configured: true)
        @member = member
        @error = error
        @configured = configured
      end

      def configured? = @configured

      def guild_member(_guild_id, _user_id)
        raise @error if @error

        @member
      end
    end

    def check(api, fallback: -> { :fallback })
      GuildMembership.call(guild_id: 1, user_id: 2, api: api, fallback: fallback)
    end

    test "a member Discord knows about is a definitive yes" do
      assert_equal true, check(FakeApi.new(member: { "user" => { "id" => "2" } }))
    end

    test "a 404 is a definitive no" do
      assert_equal false, check(FakeApi.new(error: BotApi::NotFound.new("404")))
    end

    test "no bot token falls back to the caller's snapshot" do
      assert_equal :fallback, check(FakeApi.new(configured: false))
    end

    test "a network error falls back rather than reading as not-a-member" do
      assert_equal :fallback, check(FakeApi.new(error: BotApi::Error.new("boom")))
    end

    test "the bot being locked out of the guild falls back too" do
      # Forbidden subclasses NotFound, but it means the BOT can't see the
      # guild — it says nothing about the user, so it must not become "no".
      assert_equal :fallback, check(FakeApi.new(error: BotApi::Forbidden.new("403")))
    end
  end
end
