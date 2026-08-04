require "test_helper"

module BattleNet
  class RefreshCharacterTest < ActiveSupport::TestCase
    # Stands in for BattleNet::Client. Values may be payload hashes or exception
    # classes to raise.
    class FakeClient
      attr_reader :calls

      def initialize(profile:, keystone: nil)
        @profile = profile
        @keystone = keystone
        @calls = []
      end

      def character_profile(realm, name)
        @calls << [ :profile, realm, name ]
        raise @profile if error?(@profile)

        @profile
      end

      def mythic_keystone_profile(realm, name)
        @calls << [ :keystone, realm, name ]
        raise @keystone if error?(@keystone)

        @keystone
      end

      private

      def error?(v) = v.is_a?(Class) && v <= StandardError
    end

    PROFILE = {
      "name" => "Morhigahn",
      "level" => 80,
      "equipped_item_level" => 636,
      "average_item_level" => 641,
      "active_spec" => { "name" => "Enhancement", "id" => 263 },
      "character_class" => { "name" => "Shaman", "id" => 7 },
      "race" => { "name" => "Draenei", "id" => 11 },
      "faction" => { "type" => "ALLIANCE", "name" => "Alliance" },
      "guild" => { "name" => "Liquid", "id" => 1 },
      "last_login_timestamp" => 1_753_000_000_000
    }.freeze

    KEYSTONE = { "current_mythic_rating" => { "rating" => 2543.72 } }.freeze

    def account
      @account ||= users(:member).battle_net_accounts.create!(
        battle_net_id: 1, battle_tag: "Thrall#1234", region: "us", linked_at: Time.current
      )
    end

    def character(**overrides)
      account.wow_characters.create!({
        blizzard_id: 42, name: "Morhigahn", realm: "Sargeras", realm_slug: "sargeras",
        level: 80, playable_class: "Shaman", verified_at: Time.current
      }.merge(overrides))
    end

    def refresh(char, profile: PROFILE, keystone: KEYSTONE)
      client = FakeClient.new(profile: profile, keystone: keystone)
      [ RefreshCharacter.call(char, client: client), client ]
    end

    test "pulls gear, spec, guild and M+ score onto the character" do
      char = character
      result, = refresh(char)

      assert result.ok?, result.status
      char.reload
      assert_equal 636, char.item_level
      assert_equal 641, char.average_item_level
      assert_equal 641, char.ilvl, "ilvl is the average — the number Blizzard's armory shows"
      assert_equal "Enhancement", char.active_spec
      assert_equal "Liquid", char.guild_name
      assert_equal 2544, char.mythic_score
      assert_equal "Enhancement Shaman", char.spec_and_class
      assert char.refreshed_at.present?
      assert_not char.missing?
    end

    test "addresses Blizzard by realm slug and name" do
      _result, client = refresh(character)

      assert_equal [ [ :profile, "sargeras", "Morhigahn" ], [ :keystone, "sargeras", "Morhigahn" ] ], client.calls
    end

    # Blizzard 404s the keystone endpoint for anyone who hasn't run a key this
    # season. That's ordinary, not a failure.
    test "a character with no keys this season still refreshes" do
      char = character
      result, = refresh(char, keystone: Client::NotFound)

      assert result.ok?, result.status
      assert_nil char.reload.mythic_rating
      assert_equal 641, char.average_item_level, "the gear half must still land"
    end

    test "a missing keystone rating is not treated as a zero score" do
      char = character
      refresh(char, keystone: { "current_period" => {} })

      assert_nil char.reload.mythic_score
    end

    # The public endpoint is addressed by name, so a rename or transfer reads as
    # a 404 and can't be followed.
    test "a character Blizzard no longer knows is marked missing, not destroyed" do
      char = character
      result, = refresh(char, profile: Client::NotFound)

      assert_equal :missing, result.status
      char.reload
      assert char.missing?
      assert char.refreshed_at.present?, "stamped so the sweep stops hammering it"
      assert_equal "Morhigahn", char.name, "last known data is kept"
    end

    test "a character that comes back clears its missing flag" do
      char = character(missing_at: 2.days.ago)
      result, = refresh(char)

      assert result.ok?
      assert_not char.reload.missing?
    end

    test "transient Blizzard failures propagate so the job can retry" do
      assert_raises(Client::Error) { refresh(character, profile: Client::Error) }
    end

    test "an expired app token propagates rather than being recorded as missing" do
      char = character

      assert_raises(Client::Unauthorized) { refresh(char, profile: Client::Unauthorized) }
      assert_not char.reload.missing?
    end

    test "keeps existing values when Blizzard omits a field" do
      char = character
      refresh(char, profile: { "name" => "Morhigahn", "level" => 80 })

      char.reload
      assert_equal "Shaman", char.playable_class, "not blanked by an absent field"
      assert_nil char.item_level
    end

    test "handles localized objects if Blizzard ignores the locale param" do
      char = character
      refresh(char, profile: PROFILE.merge("active_spec" => { "name" => { "en_US" => "Resto" } }))

      assert_equal "Resto", char.reload.active_spec
    end
  end
end
