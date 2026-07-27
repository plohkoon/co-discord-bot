require "test_helper"

module BattleNet
  class LinkAccountTest < ActiveSupport::TestCase
    BNET_ID = 987_654_321

    # Stands in for BattleNet::Client. `profiles` maps region => the
    # /profile/user/wow payload, or an exception class to raise instead.
    class FakeClient
      attr_reader :calls

      def initialize(profiles)
        @profiles = profiles
        @calls = []
      end

      def region_client(region)
        @calls << region
        Region.new(@profiles[region])
      end

      class Region
        def initialize(payload)
          @payload = payload
        end

        def wow_account_profile
          raise @payload if @payload.is_a?(Class) && @payload <= StandardError

          @payload
        end
      end
    end

    def auth(uid: BNET_ID, battletag: "Thrall#1234")
      OmniAuth::AuthHash.new(
        provider: "battle_net",
        uid: uid.to_s,
        info: { battletag: battletag },
        credentials: { token: "user-token" },
        extra: { raw_info: { "id" => uid, "battletag" => battletag } }
      )
    end

    def character(id:, name:, realm: "Illidan", slug: "illidan", level: 80, klass: "Shaman")
      {
        "id" => id,
        "name" => name,
        "level" => level,
        "realm" => { "id" => 57, "name" => realm, "slug" => slug },
        "playable_class" => { "id" => 7, "name" => klass },
        "playable_race" => { "id" => 2, "name" => "Orc" },
        "faction" => { "type" => "HORDE", "name" => "Horde" }
      }
    end

    def profile(*characters)
      { "id" => BNET_ID, "wow_accounts" => [ { "id" => 1, "characters" => characters } ] }
    end

    def link(profiles:, user: users(:member), preferred_region: "us")
      fake = FakeClient.new(profiles)
      result = LinkAccount.call(
        user: user, auth: auth, preferred_region: preferred_region,
        client_for: ->(region) { fake.region_client(region) }
      )
      [ result, fake ]
    end

    test "captures the Battle.net identity and every character Blizzard returns" do
      result, = link(profiles: { "us" => profile(character(id: 1, name: "Thrall"),
                                                 character(id: 2, name: "Jaina", klass: "Mage")) })

      assert result.ok?, result.error
      account = result.account
      assert_equal BNET_ID, account.battle_net_id
      assert_equal "Thrall#1234", account.battle_tag
      assert_equal "us", account.region
      assert_equal users(:member), account.user
      assert_equal %w[Jaina Thrall], account.wow_characters.pluck(:name).sort
    end

    test "marks characters verified because they came back on the owner's own token" do
      result, = link(profiles: { "us" => profile(character(id: 1, name: "Thrall")) })

      thrall = result.account.wow_characters.sole
      assert thrall.verified?
      assert_equal "Thrall-Illidan", thrall.full_name
      assert_equal "illidan", thrall.realm_slug
      assert_equal "horde", thrall.faction
      assert_equal "Shaman", thrall.playable_class
    end

    test "stops at the preferred region when it has characters" do
      _result, fake = link(profiles: { "us" => profile(character(id: 1, name: "Thrall")),
                                       "eu" => profile(character(id: 2, name: "Sylvanas")) })

      assert_equal [ "us" ], fake.calls
    end

    test "finds characters in another region when the preferred one is empty" do
      result, fake = link(profiles: { "us" => profile,
                                      "eu" => profile(character(id: 2, name: "Sylvanas")) })

      assert result.ok?, result.error
      assert_equal "eu", result.account.region
      assert_equal [ "Sylvanas" ], result.account.wow_characters.pluck(:name)
      assert_includes fake.calls, "eu"
    end

    test "re-linking adds new characters and drops ones Blizzard no longer reports" do
      link(profiles: { "us" => profile(character(id: 1, name: "Thrall"),
                                       character(id: 2, name: "Jaina")) })
      result, = link(profiles: { "us" => profile(character(id: 1, name: "Thrall"),
                                                 character(id: 3, name: "Anduin")) })

      assert result.ok?, result.error
      assert_equal 1, BattleNetAccount.count, "re-linking must update the existing row, not add one"
      assert_equal %w[Anduin Thrall], result.account.wow_characters.pluck(:name).sort
    end

    test "a rename is applied to the existing row because the Blizzard id is the key" do
      link(profiles: { "us" => profile(character(id: 1, name: "Thrall")) })
      result, = link(profiles: { "us" => profile(character(id: 1, name: "Thrallz")) })

      assert_equal [ "Thrallz" ], result.account.wow_characters.pluck(:name)
      assert_equal 1, WowCharacter.count
    end

    test "an account with no characters still links" do
      result, = link(profiles: { "us" => profile })

      assert result.ok?, result.error
      assert_empty result.account.wow_characters
    end

    test "a rejected token fails the link without writing anything" do
      result, = link(profiles: { "us" => Client::Unauthorized })

      assert_not result.ok?
      assert_match(/linking again/i, result.error)
      assert_equal 0, BattleNetAccount.count
    end

    test "an unreachable Blizzard fails the link rather than storing an empty roster" do
      result, = link(profiles: { "us" => Client::Error, "eu" => Client::Error,
                                 "tw" => Client::Error, "kr" => Client::Error })

      assert_not result.ok?
      assert_equal 0, BattleNetAccount.count
    end

    test "two users may link their own Battle.net accounts independently" do
      link(profiles: { "us" => profile(character(id: 1, name: "Thrall")) }, user: users(:member))
      link(profiles: { "us" => profile(character(id: 9, name: "Greg")) }, user: users(:admin))

      assert_equal 2, BattleNetAccount.count
      assert_equal 1, users(:member).battle_net_accounts.sole.wow_characters.count
    end

    test "skips malformed character entries instead of failing the whole link" do
      result, = link(profiles: { "us" => profile(character(id: 1, name: "Thrall"),
                                                 { "id" => 2, "name" => "Broken" }) }) # no realm

      assert result.ok?, result.error
      assert_equal [ "Thrall" ], result.account.wow_characters.pluck(:name)
    end
  end
end
