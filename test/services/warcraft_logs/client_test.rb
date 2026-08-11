require "test_helper"

module WarcraftLogs
  class ClientTest < ActiveSupport::TestCase
    def intercept(code: "200", body: {})
      captured = nil
      original = Net::HTTP.method(:start)
      Net::HTTP.define_singleton_method(:start) do |*_a, **_k, &block|
        http = Object.new
        http.define_singleton_method(:request) do |request|
          captured = request
          response = Net::HTTPResponse.send(:response_class, code).new("1.1", code, "OK")
          response.instance_variable_set(:@body, body.is_a?(String) ? body : JSON.generate(body))
          response.instance_variable_set(:@read, true)
          response
        end
        block.call(http)
      end
      result = yield
      [ captured, result ]
    ensure
      Net::HTTP.define_singleton_method(:start, original)
    end

    def client = Client.new(token: "test-token")

    test "posts a GraphQL document with variables and a bearer token" do
      request, = intercept(body: { "data" => { "worldData" => { "zones" => [] } } }) do
        client.zones(expansion_id: 11)
      end

      assert_equal "www.warcraftlogs.com", request.uri.host
      assert_equal "/api/v2/client", request.uri.path
      assert_equal "Bearer test-token", request["Authorization"]
      body = JSON.parse(request.body)
      assert_includes body["query"], "worldData"
      assert_equal({ "expansionID" => 11 }, body["variables"])
    end

    test "nil variables are dropped rather than sent as explicit nulls" do
      request, = intercept(body: { "data" => { "worldData" => { "zones" => [] } } }) do
        client.zones
      end

      assert_empty JSON.parse(request.body)["variables"]
    end

    test "region is upcased, which is the form Warcraft Logs expects" do
      payload = { "data" => { "characterData" => { "character" => { "id" => 1 } } } }
      request, = intercept(body: payload) do
        client.character_zone_rankings(name: "Thrall", server_slug: "sargeras", region: "us")
      end

      assert_equal "US", JSON.parse(request.body)["variables"]["serverRegion"]
    end

    # The one that catches people out: GraphQL reports failures inside an HTTP
    # 200, so the status code alone proves nothing.
    test "an error reported inside a 200 response is still an error" do
      body = { "errors" => [ { "message" => "Internal server error" } ] }

      assert_raises(Client::Error) { intercept(body: body) { client.zones } }
    end

    test "a rate-limit error inside a 200 is classified as RateLimited" do
      body = { "errors" => [ { "message" => "You have exceeded the rate limit of points per hour." } ] }

      assert_raises(Client::RateLimited) { intercept(body: body) { client.zones } }
    end

    test "an auth error inside a 200 is classified as Unauthorized" do
      body = { "errors" => [ { "message" => "Unauthenticated." } ] }

      assert_raises(Client::Unauthorized) { intercept(body: body) { client.zones } }
    end

    # `characterData.character` comes back null for someone who has never been
    # in a logged raid — a successful query with an empty answer.
    test "a null character is a NotFound, not a malformed response" do
      body = { "data" => { "characterData" => { "character" => nil } } }

      assert_raises(Client::NotFound) do
        intercept(body: body) { client.character_zone_rankings(name: "Nobody", server_slug: "s", region: "us") }
      end
    end

    test "HTTP-level auth and rate-limit failures are classified too" do
      assert_raises(Client::Unauthorized) { intercept(code: "401") { client.zones } }
      assert_raises(Client::RateLimited) { intercept(code: "429") { client.zones } }
      assert_raises(Client::Error) { intercept(code: "500") { client.zones } }
    end

    test "configured? is false without credentials, so callers can skip cleanly" do
      original = { "WARCRAFTLOGS_CLIENT_ID" => ENV["WARCRAFTLOGS_CLIENT_ID"],
                   "WARCRAFTLOGS_CLIENT_SECRET" => ENV["WARCRAFTLOGS_CLIENT_SECRET"] }
      original.each_key { |k| ENV.delete(k) }

      assert_not Client.configured?
      assert_raises(Client::Error) { Client.access_token }
    ensure
      original.each { |k, v| v.nil? ? ENV.delete(k) : ENV[k] = v }
    end
  end
end
