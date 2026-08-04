require "test_helper"

module WowAudit
  class SyncRosterTest < ActiveSupport::TestCase
    NOW = Time.utc(2026, 7, 27)

    class FakeClient
      def initialize(roster, error: nil)
        @roster = roster
        @error = error
      end

      def configured? = true

      def characters
        raise @error if @error

        @roster
      end
    end

    # Shape confirmed against wowaudit's live API via two independent clients:
    # a top-level array of {id, name, realm, class, role}.
    def entry(id, name, realm: "Sargeras", klass: "Death Knight", role: "Tank")
      { "id" => id, "name" => name, "realm" => realm, "class" => klass, "role" => role }
    end

    def guild = @guild ||= Guild.create!(id: 777_000_111_222_333_444, name: "Raid Server")

    def team
      @team ||= ActsAsTenant.with_tenant(guild) do
        Team.create!(name: "Alpha", team_role_id: 1, officer_role_id: 2, review_channel_id: 3,
                     wowaudit_api_key: "test-key")
      end
    end

    def linked_character(name:, realm: "Sargeras")
      account = users(:member).battle_net_accounts.find_or_create_by!(battle_net_id: 1) do |a|
        a.region = "us"
        a.linked_at = NOW
      end
      account.wow_characters.create!(
        blizzard_id: name.hash.abs, name: name, realm: realm,
        realm_slug: realm.downcase, level: 90, verified_at: NOW
      )
    end

    def sync(roster, error: nil)
      ActsAsTenant.with_tenant(guild) do
        SyncRoster.call(team, client: FakeClient.new(roster, error: error), now: NOW)
      end
    end

    test "stores the roster wowaudit reports" do
      result = sync([ entry(1, "Jörmûngandr"), entry(2, "Morhigahn", role: "Dps") ])

      assert result.ok?, result.error
      assert_equal 2, result.synced
      rows = team.wowaudit_characters.by_name
      assert_equal %w[Jörmûngandr Morhigahn], rows.map(&:name)
      assert_equal "Death Knight", rows.first.character_class
      assert_equal "tank", rows.first.role, "role is normalised"
      assert_equal "Jörmûngandr-Sargeras", rows.first.full_name
    end

    test "matches roster entries to characters we already know" do
      linked = linked_character(name: "Jörmûngandr")
      result = sync([ entry(1, "Jörmûngandr"), entry(2, "Stranger") ])

      assert_equal 1, result.matched
      assert_equal linked.id, team.wowaudit_characters.find_by(wowaudit_id: 1).wow_character_id
      assert_nil team.wowaudit_characters.find_by(wowaudit_id: 2).wow_character_id
    end

    # Case and realm spacing differ between wowaudit and Blizzard, so the match
    # has to normalise or it silently never fires.
    test "the name match survives case and realm spelling differences" do
      linked = linked_character(name: "Khassandrah", realm: "Area 52")
      sync([ entry(1, "khassandrah", realm: "Area-52") ])

      assert_equal linked.id, team.wowaudit_characters.sole.wow_character_id
    end

    # Most rosters include people who've never linked Battle.net here.
    test "an unmatched entry is stored, not dropped" do
      sync([ entry(1, "NeverLinked") ])

      row = team.wowaudit_characters.sole
      assert_not row.matched?
      assert_equal "NeverLinked", row.name
      assert_equal 1, team.wowaudit_characters.unmatched.count
    end

    test "re-syncing updates in place and drops people taken off the roster" do
      sync([ entry(1, "Stays"), entry(2, "Leaves") ])
      result = sync([ entry(1, "Stays", role: "Healer"), entry(3, "Joins") ])

      assert_equal 1, result.removed
      assert_equal %w[Joins Stays], team.wowaudit_characters.by_name.map(&:name)
      assert_equal "healer", team.wowaudit_characters.find_by(wowaudit_id: 1).role
    end

    test "an empty roster clears the stored one" do
      sync([ entry(1, "Someone") ])
      result = sync([])

      assert result.ok?
      assert_equal 0, team.wowaudit_characters.count
    end

    test "syncing marks the key verified" do
      sync([ entry(1, "Someone") ])

      assert team.reload.wowaudit_verified?
    end

    test "a rejected key clears the verified stamp and keeps the roster" do
      sync([ entry(1, "Someone") ])
      result = sync([], error: Client::Unauthorized)

      assert_not result.ok?
      assert_match(/rejected the key/i, result.error)
      assert_not team.reload.wowaudit_verified?
      assert_equal 1, team.wowaudit_characters.count, "a bad key must not wipe the roster"
    end

    test "a transient failure leaves the roster untouched" do
      sync([ entry(1, "Someone") ])
      result = sync([], error: Client::RateLimited)

      assert_not result.ok?
      assert_equal 1, team.wowaudit_characters.count
    end

    test "malformed entries are skipped rather than failing the sync" do
      result = sync([ entry(1, "Fine"), { "name" => "NoId" }, { "id" => 9 }, "nonsense" ])

      assert result.ok?, result.error
      assert_equal 1, result.synced
      assert_equal %w[Fine], team.wowaudit_characters.map(&:name)
    end

    test "a team with no key fails cleanly" do
      team.update!(wowaudit_api_key: nil)
      result = ActsAsTenant.with_tenant(guild) { SyncRoster.call(team) }

      assert_not result.ok?
      assert_match(/no wowaudit api key/i, result.error)
    end
  end
end
