require "test_helper"

module BattleNet
  class ClientTest < ActiveSupport::TestCase
    # Captures the outbound request instead of sending it, so we can assert on
    # the URL Blizzard would actually receive.
    def intercept(code: "200", body: { "ok" => true })
      captured = nil
      original = Net::HTTP.method(:start)
      Net::HTTP.define_singleton_method(:start) do |*_args, **_kwargs, &block|
        # The block builds and "sends" the request; grab it and answer directly.
        http = Object.new
        http.define_singleton_method(:request) do |request|
          captured = request
          response = Net::HTTPResponse.send(:response_class, code).new("1.1", code, "OK")
          response.instance_variable_set(:@body, JSON.generate(body))
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

    def client(region: "us") = Client.for_user("user-token", region: region)

    test "account profile is requested with the region's host, namespace and locale" do
      request, = intercept { client.wow_account_profile }

      assert_equal "us.api.blizzard.com", request.uri.host
      assert_equal "/profile/user/wow", request.uri.path
      query = Rack::Utils.parse_query(request.uri.query)
      assert_equal "profile-us", query["namespace"]
      assert_equal "en_US", query["locale"]
      assert_equal "Bearer user-token", request["Authorization"]
    end

    test "the region decides both host and namespace" do
      request, = intercept { client(region: "eu").wow_account_profile }

      assert_equal "eu.api.blizzard.com", request.uri.host
      assert_equal "profile-eu", Rack::Utils.parse_query(request.uri.query)["namespace"]
    end

    test "an unsupported region falls back to the default rather than building a bad host" do
      assert_equal "us", client(region: "cn").region
      assert_equal "us", client(region: nil).region
    end

    test "character names are lowercased and escaped the way Blizzard expects" do
      request, = intercept { client.character_profile("illidan", "Ünstable") }

      assert_equal "/profile/wow/character/illidan/%C3%BCnstable", request.uri.path
    end

    test "userinfo goes to the global OAuth host, not a regional API host" do
      request, = intercept { client.userinfo }

      assert_equal "oauth.battle.net", request.uri.host
      assert_equal "/userinfo", request.uri.path
      assert_nil request.uri.query, "userinfo takes no namespace or locale"
    end

    test "401 and 403 both mean the token is no good" do
      assert_raises(Client::Unauthorized) { intercept(code: "401") { client.wow_account_profile } }
      assert_raises(Client::Unauthorized) { intercept(code: "403") { client.wow_account_profile } }
    end

    test "404 is distinguishable from a transport failure" do
      assert_raises(Client::NotFound) { intercept(code: "404") { client.character_profile("illidan", "Nobody") } }
      assert_raises(Client::Error) { intercept(code: "500") { client.character_profile("illidan", "Nobody") } }
    end

    test "app token requires credentials" do
      Client.expire_app_token
      with_env("BLIZZARD_CLIENT_ID" => nil, "BLIZZARD_CLIENT_SECRET" => nil) do
        assert_not Client.configured?
        assert_raises(Client::Error) { Client.app_token }
      end
    end

    # The test env caches into :null_store, so swap in a real store — the point
    # of this test is that every process shares one token instead of minting its
    # own on each call.
    test "the app token is fetched once and shared from the cache" do
      with_memory_cache do
        with_env("BLIZZARD_CLIENT_ID" => "id", "BLIZZARD_CLIENT_SECRET" => "secret") do
          request, token = intercept(body: { "access_token" => "app-token", "expires_in" => 86_399 }) do
            Client.app_token
          end

          assert_equal "app-token", token
          assert_equal "oauth.battle.net", request.uri.host
          assert_equal "grant_type=client_credentials", request.body
          assert request["authorization"].start_with?("Basic "), "credentials go as HTTP Basic"

          # Second call must not hit the network at all.
          second, = intercept(code: "500") { Client.app_token }
          assert_nil second, "a cached token must not trigger a second token request"
          assert_equal "app-token", Client.app_token
        end
      end
    end

    private

    def with_memory_cache
      original = Rails.cache
      Rails.cache = ActiveSupport::Cache::MemoryStore.new
      yield
    ensure
      Rails.cache = original
    end

    def with_env(values)
      original = values.keys.index_with { |k| ENV[k] }
      values.each { |k, v| v.nil? ? ENV.delete(k) : ENV[k] = v }
      yield
    ensure
      original.each { |k, v| v.nil? ? ENV.delete(k) : ENV[k] = v }
    end
  end
end
