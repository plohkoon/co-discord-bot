require "test_helper"

module Notifications
  class DirectMessageTest < ActiveSupport::TestCase
    # Stands in for Discord::BotApi — records the DM, or raises a canned error.
    class FakeApi
      attr_reader :sent

      def initialize(error: nil)
        @error = error
        @sent = []
      end

      def send_dm(user_id, payload)
        raise @error if @error

        @sent << [ user_id, payload ]
        { "id" => "1" }
      end
    end

    test "sends the content with mentions suppressed" do
      api = FakeApi.new
      DirectMessage.call(user_id: 42, content: "hello", api: api)

      assert_equal 1, api.sent.size
      user_id, payload = api.sent.first
      assert_equal 42, user_id
      assert_equal "hello", payload["content"]
      assert_equal({ "parse" => [] }, payload["allowed_mentions"])
    end

    test "a closed DM (Forbidden) is swallowed as a no-op" do
      api = FakeApi.new(error: Discord::BotApi::Forbidden.new("cannot send messages to this user"))

      assert_nil DirectMessage.call(user_id: 42, content: "hi", api: api)
    end

    test "a vanished user (NotFound) is swallowed as a no-op" do
      api = FakeApi.new(error: Discord::BotApi::NotFound.new("unknown user"))

      assert_nil DirectMessage.call(user_id: 42, content: "hi", api: api)
    end

    test "a transient error propagates so the job can retry" do
      api = FakeApi.new(error: Discord::BotApi::Error.new("rate limited"))

      assert_raises(Discord::BotApi::Error) { DirectMessage.call(user_id: 42, content: "hi", api: api) }
    end
  end
end
