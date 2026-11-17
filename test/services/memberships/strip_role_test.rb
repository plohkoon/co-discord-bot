require "test_helper"

module Memberships
  class StripRoleTest < ActiveSupport::TestCase
    ROLE = 500

    # Members 1 and 3 hold the role; 2 doesn't. Each removal answers from the
    # per-user script, defaulting to success.
    class FakeApi
      attr_reader :removed, :calls

      def initialize(script = {})
        @script = script.transform_values { |v| Array(v) }
        @removed = []
        @calls = 0
      end

      def each_guild_member(_guild_id)
        [ [ "1", [ ROLE.to_s ] ], [ "2", [ "7" ] ], [ "3", [ "7", ROLE.to_s ] ] ].each do |id, roles|
          yield({ "user" => { "id" => id }, "roles" => roles })
        end
      end

      def remove_member_role(_guild_id, user_id, role_id, reason:)
        @calls += 1
        raise ArgumentError unless role_id == ROLE && reason.present?

        outcome = @script[user_id]&.shift
        raise outcome if outcome

        @removed << user_id
      end
    end

    def strip(api, waits = [])
      StripRole.call(guild_id: 1, role_id: ROLE, reason: "co-bot: Alpha was deleted", api: api, wait: ->(s) { waits << s })
    end

    test "removes the role from exactly the members holding it" do
      api = FakeApi.new

      result = strip(api)

      assert_equal %w[1 3], api.removed
      assert_equal 2, result.removed
      assert_not result.refused
    end

    test "a rate limit waits Discord's retry_after and retries the same member" do
      api = FakeApi.new("1" => [ Discord::BotApi::RateLimited.new("429", retry_after: 1.5) ])
      waits = []

      result = strip(api, waits)

      assert_equal [ 1.5 ], waits
      assert_equal %w[1 3], api.removed
      assert_equal 2, result.removed
    end

    test "endless rate limiting gives up and leaves it to the job's retry" do
      api = FakeApi.new("1" => Array.new(StripRole::MAX_WAITS + 1) { Discord::BotApi::RateLimited.new("429") })

      assert_raises(Discord::BotApi::RateLimited) { strip(api) }
    end

    test "a member who left meanwhile is skipped, not fatal" do
      api = FakeApi.new("1" => [ Discord::BotApi::NotFound ])

      result = strip(api)

      assert_equal %w[3], api.removed
      assert_equal 1, result.removed
      assert_not result.refused
    end

    test "a refusal stops the sweep — every later request would be refused too" do
      api = FakeApi.new("1" => [ Discord::BotApi::Forbidden ])

      result = strip(api)

      assert result.refused
      assert_equal 0, result.removed
      assert_equal 1, api.calls
    end
  end
end
