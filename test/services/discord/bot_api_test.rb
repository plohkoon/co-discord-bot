require "test_helper"

module Discord
  # Exercises the DM primitives against a stubbed HTTP layer so we can assert on
  # the paths and bodies BotApi builds without touching the network. Minitest 6
  # dropped minitest/mock, so Net::HTTP.start is stubbed by redefinition.
  class BotApiTest < ActiveSupport::TestCase
    class FakeHttp
      attr_reader :requests

      def initialize(*responses)
        @responses = responses
        @requests = []
      end

      def request(req)
        @requests << req
        @responses.shift
      end
    end

    def ok(body)
      response = Net::HTTPOK.new("1.1", "200", "OK")
      response.instance_variable_set(:@read, true)
      response.instance_variable_set(:@body, body)
      response
    end

    def with_http(fake)
      original = Net::HTTP.method(:start)
      Net::HTTP.define_singleton_method(:start) { |*_args, **_kwargs, &block| block.call(fake) }
      yield
    ensure
      Net::HTTP.define_singleton_method(:start, original)
    end

    def api = Discord::BotApi.new(token: "test-token")

    test "create_dm_channel posts recipient_id and returns the channel id" do
      fake = FakeHttp.new(ok(JSON.generate("id" => "555")))

      channel_id = with_http(fake) { api.create_dm_channel(42) }

      assert_equal "555", channel_id
      assert_equal 1, fake.requests.size
      request = fake.requests.first
      assert_kind_of Net::HTTP::Post, request
      assert_equal "/api/v10/users/@me/channels", request.uri.path
      assert_equal({ "recipient_id" => "42" }, JSON.parse(request.body))
    end

    test "send_dm opens the DM channel, then posts the message there" do
      fake = FakeHttp.new(
        ok(JSON.generate("id" => "999")),                        # create_dm_channel
        ok(JSON.generate("id" => "1000", "channel_id" => "999")) # create_message
      )
      payload = { "content" => "hi", "allowed_mentions" => { "parse" => [] } }

      result = with_http(fake) { api.send_dm(42, payload) }

      assert_equal "1000", result["id"]
      open_req, send_req = fake.requests
      assert_equal "/api/v10/users/@me/channels", open_req.uri.path
      assert_equal "/api/v10/channels/999/messages", send_req.uri.path
      assert_equal payload, JSON.parse(send_req.body)
    end

    test "a closed DM maps to Forbidden" do
      forbidden = Net::HTTPForbidden.new("1.1", "403", "Forbidden")
      forbidden.instance_variable_set(:@read, true)
      forbidden.instance_variable_set(:@body, "")

      assert_raises(Discord::BotApi::Forbidden) do
        with_http(FakeHttp.new(forbidden)) { api.create_dm_channel(42) }
      end
    end
  end
end
