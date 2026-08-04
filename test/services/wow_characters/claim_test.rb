require "test_helper"

module WowCharacters
  class ClaimTest < ActiveSupport::TestCase
    NOW = Time.utc(2026, 7, 27)

    class FakeClient
      def initialize(profile, error: nil)
        @profile = profile
        @error = error
      end

      def character_profile(_realm, _name)
        raise @error if @error

        @profile
      end
    end

    def profile(id: 42, name: "Thrall", realm: "Sargeras", slug: "sargeras", level: 90)
      { "id" => id, "name" => name, "level" => level,
        "realm" => { "id" => 57, "name" => realm, "slug" => slug },
        "character_class" => { "name" => "Shaman" },
        "race" => { "name" => "Orc" },
        "faction" => { "type" => "HORDE" } }
    end

    def claim(user: users(:member), name: "Thrall", realm: "sargeras", region: "us",
              response: profile, error: nil)
      Claim.call(user: user, name: name, realm_slug: realm, region: region,
                 client: FakeClient.new(response, error: error), now: NOW)
    end

    # The whole point: no Battle.net account involved.
    test "claims a character with no Battle.net link at all" do
      result = claim

      assert result.ok?, result.error
      character = result.character
      assert_equal users(:member), character.user
      assert_nil character.battle_net_account
      assert_equal "Thrall-Sargeras", character.full_name
      assert_equal "us", character.region
      assert_equal "Shaman", character.playable_class
    end

    # A claim is an assertion, not proof, and everything downstream depends on
    # being able to tell the difference.
    test "a claim is never verified" do
      character = claim.character

      assert character.claimed?
      assert_not character.verified?
      assert_equal :claimed, character.ownership
      assert_not character.proven?
    end

    test "the character is validated against Blizzard before being stored" do
      result = claim(error: BattleNet::Client::NotFound)

      assert_not result.ok?
      assert_match(/no character called/i, result.error)
      assert_equal 0, WowCharacter.count
    end

    test "a blank name or realm is rejected without a request" do
      assert_not claim(name: "").ok?
      assert_not claim(realm: "").ok?
    end

    test "re-claiming your own character is a no-op, not a duplicate" do
      claim
      result = claim

      assert result.ok?
      assert_equal :already_yours, result.status
      assert_equal 1, WowCharacter.count
    end

    # --- Conflicts ---
    #
    # A claim is the weakest signal in the system; it must never be able to take
    # a character away from someone.

    test "a character someone else verified cannot be claimed" do
      other = users(:admin).battle_net_accounts.create!(battle_net_id: 9, region: "us", linked_at: NOW)
      other.wow_characters.create!(blizzard_id: 42, name: "Thrall", realm: "Sargeras",
                                   realm_slug: "sargeras", verified_at: NOW)

      result = claim

      assert_not result.ok?
      assert_match(/already linked to another account/i, result.error)
      assert_equal users(:admin), WowCharacter.sole.user
    end

    test "a character someone else claimed cannot be taken by another claim" do
      claim(user: users(:admin))
      result = claim(user: users(:member))

      assert_not result.ok?
      assert_match(/already claimed/i, result.error)
      assert_equal users(:admin), WowCharacter.sole.user
    end

    # --- Convergence with the OAuth link ---

    test "verifying a claimed character upgrades the same row rather than forking" do
      character = claim.character
      assert character.claimed?

      account = users(:member).battle_net_accounts.create!(battle_net_id: 1, region: "us", linked_at: NOW)
      character.update!(battle_net_account: account, verified_at: NOW)

      assert_equal 1, WowCharacter.count
      character.reload
      assert character.verified?
      assert character.claimed?, "the claim is still true; it's just no longer the only evidence"
      assert_equal :verified, character.ownership
    end

    test "claiming a character you already verified does not downgrade it" do
      account = users(:member).battle_net_accounts.create!(battle_net_id: 1, region: "us", linked_at: NOW)
      account.wow_characters.create!(blizzard_id: 42, name: "Thrall", realm: "Sargeras",
                                     realm_slug: "sargeras", verified_at: NOW)

      result = claim

      assert result.ok?
      assert result.character.verified?, "still proven"
      assert_equal :verified, result.character.ownership
    end

    test "an unreachable Blizzard fails the claim rather than storing an unchecked name" do
      result = claim(error: BattleNet::Client::Error)

      assert_not result.ok?
      assert_equal 0, WowCharacter.count
    end

    test "an unknown region falls back to the default rather than storing a bad one" do
      character = claim(region: "cn").character

      assert_equal "us", character.region
    end
  end
end
