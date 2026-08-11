require "test_helper"

module Discord
  class ConnectionsTest < ActiveSupport::TestCase
    def stub_response(body, code: "200")
      response = Net::HTTPResponse.send(:response_class, code).new("1.1", code, "OK")
      response.instance_variable_set(:@body, body.is_a?(String) ? body : JSON.generate(body))
      response.instance_variable_set(:@read, true)
      response
    end

    def with_response(response)
      original = Net::HTTP.method(:start)
      Net::HTTP.define_singleton_method(:start) { |*, **, &_block| response }
      yield
    ensure
      Net::HTTP.define_singleton_method(:start, original)
    end

    PAYLOAD = [
      { "type" => "battlenet", "id" => "123456789", "name" => "Thrall#1234", "verified" => true },
      { "type" => "steam",     "id" => "7656119",   "name" => "thrall",      "verified" => true },
      { "type" => "battlenet", "id" => "999",       "name" => "Alt#4321",    "verified" => false }
    ].freeze

    test "maps Discord's payload into connections" do
      connections = with_response(stub_response(PAYLOAD)) { Connections.call(token: "t") }

      assert_equal 3, connections.size
      assert_equal %w[battlenet steam battlenet], connections.map(&:type)
      assert_equal "Thrall#1234", connections.first.name
      assert connections.first.verified?
    end

    test "battle_net picks the verified Battle.net link" do
      connection = with_response(stub_response(PAYLOAD)) { Connections.battle_net(token: "t") }

      assert_equal "123456789", connection.id
      assert_equal "Thrall#1234", connection.name
    end

    test "an unverified Battle.net link is not treated as one" do
      payload = [ { "type" => "battlenet", "id" => "9", "name" => "Alt#1", "verified" => false } ]

      assert_nil with_response(stub_response(payload)) { Connections.battle_net(token: "t") }
    end

    # A user who authorized before we asked for the `connections` scope gets a
    # 401 here. Sign-in must survive it.
    test "returns nothing when Discord refuses the scope" do
      connections = with_response(stub_response({ "message" => "401: Unauthorized" }, code: "401")) do
        Connections.call(token: "t")
      end

      assert_empty connections
    end

    test "returns nothing when the request blows up" do
      original = Net::HTTP.method(:start)
      Net::HTTP.define_singleton_method(:start) { |*, **, &_b| raise Errno::ECONNREFUSED }
      assert_empty Connections.call(token: "t")
    ensure
      Net::HTTP.define_singleton_method(:start, original)
    end
  end
end
