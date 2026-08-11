require "test_helper"

module Memberships
  # The REST grant path must tell "member hasn't joined" (expected — the
  # accept proceeds with the role deferred) apart from every real refusal.
  # Discord's 404 doesn't name the missing resource, so grant disambiguates
  # with a member probe.
  class RestRoleManagerTest < ActiveSupport::TestCase
    class FakeApi
      def initialize(add: :ok, member: :ok)
        @add = add
        @member = member
      end

      def add_member_role(_guild_id, _user_id, _role_id, reason: nil)
        raise_error(@add)
      end

      def guild_member(_guild_id, _user_id)
        raise_error(@member)
        { "user" => { "id" => "42" }, "roles" => [] }
      end

      private

      def raise_error(kind)
        case kind
        when :not_found then raise Discord::BotApi::NotFound, "404"
        when :forbidden then raise Discord::BotApi::Forbidden, "403"
        end
      end
    end

    def team
      @team ||= begin
        guild = Guild.sync_from_discord(id: 1, name: "Test")
        ActsAsTenant.with_tenant(guild) do
          Team.create!(name: "Alpha", team_role_id: 5, officer_role_id: 6, review_channel_id: 7)
        end
      end
    end

    def grant(api) = RestRoleManager.grant(team: team, discord_user_id: 42, api: api)

    test "a 404 for a member who isn't in the guild raises the expected MemberNotInGuild" do
      error = assert_raises(MemberNotInGuild) do
        grant(FakeApi.new(add: :not_found, member: :not_found))
      end
      assert_match(/isn't in the server/, error.message)
    end

    test "a 404 with the member present means the role vanished — a real RoleError" do
      error = assert_raises(RoleError) do
        grant(FakeApi.new(add: :not_found, member: :ok))
      end
      assert_not_kind_of MemberNotInGuild, error
      assert_match(/team role no longer exists/, error.message)
    end

    test "a 403 refusal stays a plain RoleError — hierarchy problems must surface" do
      error = assert_raises(RoleError) do
        grant(FakeApi.new(add: :forbidden))
      end
      assert_not_kind_of MemberNotInGuild, error
      assert_match(/Manage Roles/, error.message)
    end

    test "a 403 on the disambiguation probe is a refusal too, never a quiet skip" do
      error = assert_raises(RoleError) do
        grant(FakeApi.new(add: :not_found, member: :forbidden))
      end
      assert_not_kind_of MemberNotInGuild, error
      assert_match(/Manage Roles/, error.message)
    end
  end
end
