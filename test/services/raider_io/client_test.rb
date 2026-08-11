require "test_helper"

module RaiderIo
  class ClientTest < ActiveSupport::TestCase
    def intercept(code: "200", body: { "ok" => true })
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

    def query(request) = Rack::Utils.parse_query(request.uri.query)

    test "builds a character profile request with the documented fields" do
      request, = intercept do
        Client.new(api_key: nil).character_profile(region: "us", realm: "sargeras", name: "Thrall")
      end

      assert_equal "raider.io", request.uri.host
      assert_equal "/api/v1/characters/profile", request.uri.path
      params = query(request)
      assert_equal "us", params["region"]
      assert_equal "sargeras", params["realm"]
      assert_equal "Thrall", params["name"]
      assert_equal Client::CHARACTER_FIELDS.join(","), params["fields"]
      assert_nil params["access_key"], "no key configured means no key sent"
    end

    test "accented names survive as query parameters" do
      request, = intercept do
        Client.new(api_key: nil).character_profile(region: "us", realm: "sargeras", name: "Jörmûngandr")
      end

      assert_equal "Jörmûngandr", query(request)["name"]
      assert_includes request.uri.query, "J%C3%B6rm%C3%BBngandr"
    end

    test "an API key is sent when configured" do
      request, = intercept do
        Client.new(api_key: "secret").character_profile(region: "us", realm: "s", name: "n")
      end

      assert_equal "secret", query(request)["access_key"]
    end

    # The one that bites: Raider.io answers an unknown character with 400, not
    # 404, so a generic "400 = our bug" reading would misclassify every alt it
    # has never crawled.
    test "400 'could not find' is a NotFound, not a generic error" do
      body = { "statusCode" => 400, "error" => "Bad Request",
               "message" => "Could not find requested character" }

      assert_raises(Client::NotFound) do
        intercept(code: "400", body: body) do
          Client.new(api_key: nil).character_profile(region: "us", realm: "s", name: "nobody")
        end
      end
    end

    test "a genuinely malformed 400 stays a hard error" do
      body = { "statusCode" => 400, "message" => "Invalid field requested: nonsense" }

      assert_raises(Client::Error) do
        intercept(code: "400", body: body) do
          Client.new(api_key: nil).character_profile(region: "us", realm: "s", name: "n")
        end
      end
    end

    test "429 is distinguishable so callers can back off rather than retry tightly" do
      assert_raises(Client::RateLimited) do
        intercept(code: "429") { Client.new(api_key: nil).character_profile(region: "us", realm: "s", name: "n") }
      end
    end

    test "server errors are retryable errors" do
      assert_raises(Client::Error) do
        intercept(code: "503") { Client.new(api_key: nil).character_profile(region: "us", realm: "s", name: "n") }
      end
    end
  end
end
