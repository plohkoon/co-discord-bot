require "test_helper"

class WowCharacterRefreshJobTest < ActiveJob::TestCase
  class FakeClient
    def initialize(pvp_brackets: {}) = @pvp_brackets = pvp_brackets

    def character_profile(_realm, name) = { "name" => name, "level" => 80, "average_item_level" => 640 }
    def mythic_keystone_profile(_realm, _name) = { "current_mythic_rating" => { "rating" => 2100.0 } }

    # PvP rides on the same Blizzard client as gear, so the fake carries it too.
    def pvp_summary(_realm, _name)
      { "honor_level" => 42, "honorable_kills" => 500,
        "brackets" => @pvp_brackets.keys.map { |b| { "href" => "https://x/pvp-bracket/#{b}?ns=y" } } }
    end

    def pvp_bracket(_realm, _name, bracket)
      @pvp_brackets.fetch(bracket) { raise BattleNet::Client::NotFound, bracket }
    end

    def character_professions(_realm, _name)
      { "primaries" => [ { "profession" => { "id" => 197, "name" => "Tailoring" },
                           "tiers" => [ { "tier" => { "id" => 2910, "name" => "Midnight Tailoring" },
                                          "skill_points" => 30, "max_skill_points" => 100 } ] } ] }
    end
  end

  # Returns the one character in the account profile below, so linking and
  # refreshing can be exercised against the same row.
  class FakeLinkClient
    def wow_account_profile
      { "wow_accounts" => [ { "characters" => [ {
        "id" => 42, "name" => "Morhigahn", "level" => 80,
        "realm" => { "name" => "Sargeras", "slug" => "sargeras" }
      } ] } ] }
    end
  end

  def account
    @account ||= users(:member).battle_net_accounts.create!(
      battle_net_id: 1, region: "us", linked_at: Time.current
    )
  end

  def character
    @character ||= account.wow_characters.create!(
      blizzard_id: 42, name: "Morhigahn", realm: "Sargeras", realm_slug: "sargeras",
      level: 80, verified_at: Time.current
    )
  end

  class FakeRaiderIo
    def initialize(error: nil) = @error = error
    def character_profile(region:, realm:, name:, fields: nil)
      raise @error if @error

      { "active_spec_role" => "TANK",
        "mythic_plus_scores_by_season" => [
          { "season" => "season-mn-1", "scores" => { "all" => 2903.6, "tank" => 2903.6 } }
        ],
        "raid_progression" => { "tier-mn-1" => { "summary" => "1/9 M", "total_bosses" => 9,
                                                 "mythic_bosses_killed" => 1 } } }
    end
  end

  test "refreshes the character from both Blizzard and Raider.io" do
    WowCharacterRefreshJob.perform_now(character.id, client: FakeClient.new, raider_io: FakeRaiderIo.new)

    character.reload
    assert_equal 640, character.average_item_level, "Blizzard: gear"
    assert_equal "tank", character.role, "Raider.io: role"
    assert_equal "1/9 M", character.raid_progress_headline, "Raider.io: raid progression"
    assert_equal 2904, character.mythic_score
  end

  # Raider.io is supplementary. Its rate limit is far tighter than Blizzard's,
  # so letting it fail the job would re-spend Blizzard requests to fix a
  # Raider.io problem.
  test "a Raider.io failure does not lose the Blizzard data or fail the job" do
    assert_nothing_raised do
      WowCharacterRefreshJob.perform_now(
        character.id, client: FakeClient.new,
        raider_io: FakeRaiderIo.new(error: RaiderIo::Client::RateLimited)
      )
    end

    character.reload
    assert_equal 640, character.average_item_level, "Blizzard's half is already committed"
    assert_nil character.raider_io_role
    assert_no_enqueued_jobs only: WowCharacterRefreshJob
  end

  class FakeWarcraftLogs
    def initialize(error: nil) = @error = error
    def character_zone_rankings(name:, server_slug:, region:, zone_id: nil, difficulty: nil, metric: "default")
      raise @error if @error

      { "id" => 1, "zoneRankings" => { "difficulty" => 5, "medianPerformanceAverage" => 88.0,
                                       "rankings" => [ { "totalKills" => 5 } ] } }
    end
  end

  # Warcraft Logs is optional infrastructure — the WoW pipeline has to work for
  # anyone who hasn't configured it.
  # Explicitly unset rather than assuming the environment lacks them — a
  # developer who has configured Warcraft Logs must still see this pass.
  test "without Warcraft Logs credentials the refresh still completes" do
    original = %w[WARCRAFTLOGS_CLIENT_ID WARCRAFTLOGS_CLIENT_SECRET].index_with { |k| ENV[k] }
    original.each_key { |k| ENV.delete(k) }
    assert_not WarcraftLogs::Client.configured?

    WowCharacterRefreshJob.perform_now(character.id, client: FakeClient.new, raider_io: FakeRaiderIo.new)

    character.reload
    assert_equal 640, character.average_item_level
    assert_equal "tank", character.role
    assert_empty character.warcraft_logs_rankings
    assert_nil character.warcraft_logs_refreshed_at
  ensure
    original&.each { |k, v| v.nil? ? ENV.delete(k) : ENV[k] = v }
  end

  # PvP shares the Blizzard client, so it needs no extra credentials and lands
  # in the same pass as gear.
  test "PvP ratings land alongside the Blizzard gear refresh" do
    WowPvpSeason.create!(blizzard_id: 41, name: "PvP (Midnight Season 1)", current: true)
    client = FakeClient.new(pvp_brackets: {
      "3v3" => { "rating" => 3163, "tier" => { "id" => 14 }, "season" => { "id" => 41 },
                 "season_match_statistics" => { "played" => 391, "won" => 251, "lost" => 140 } }
    })

    WowCharacterRefreshJob.perform_now(character.id, client: client, raider_io: FakeRaiderIo.new)

    character.reload
    assert_equal 640, character.average_item_level, "gear still lands"
    assert_equal 3163, character.pvp_rating
    assert_equal 42, character.honor_level
  end

  # An application posts saying "Loading raider data…" and waits on exactly
  # this. The refresh is what knows when there is something to show, so it —
  # not the resolver — is what repaints.
  test "a pending application riding on this character is repainted" do
    guild = Guild.create!(id: 777_000_111_222_333_444, name: "Raid Server")
    repainted = []
    ActsAsTenant.with_tenant(guild) do
      team = Team.create!(name: "Alpha", team_role_id: 1, officer_role_id: 2, review_channel_id: 3)
      TeamApplication.create!(team: team, discord_user_id: users(:member).discord_id,
                              discord_username: "applicant", character_input: "Thrall-Sargeras",
                              wow_character: character, character_resolved_at: Time.current)
    end

    original = Applications::RefreshReviewMessage.method(:call)
    Applications::RefreshReviewMessage.define_singleton_method(:call) { |app, **| repainted << app.id }
    WowCharacterRefreshJob.perform_now(character.id, client: FakeClient.new, raider_io: FakeRaiderIo.new)

    assert_equal 1, repainted.size
  ensure
    Applications::RefreshReviewMessage.define_singleton_method(:call, original) if original
  end

  # A settled application's message is already final; repainting it would be
  # noise, and the hourly sweep would do it forever.
  test "a decided application is not repainted" do
    guild = Guild.create!(id: 777_000_111_222_333_444, name: "Raid Server")
    repainted = []
    ActsAsTenant.with_tenant(guild) do
      team = Team.create!(name: "Alpha", team_role_id: 1, officer_role_id: 2, review_channel_id: 3)
      TeamApplication.create!(team: team, discord_user_id: users(:member).discord_id,
                              discord_username: "applicant", wow_character: character,
                              status: :accepted)
    end

    original = Applications::RefreshReviewMessage.method(:call)
    Applications::RefreshReviewMessage.define_singleton_method(:call) { |app, **| repainted << app.id }
    WowCharacterRefreshJob.perform_now(character.id, client: FakeClient.new, raider_io: FakeRaiderIo.new)

    assert_empty repainted
  ensure
    Applications::RefreshReviewMessage.define_singleton_method(:call, original) if original
  end

  test "professions land in the same pass" do
    WowCharacterRefreshJob.perform_now(character.id, client: FakeClient.new, raider_io: FakeRaiderIo.new)

    assert_equal "Tailoring 30/100", character.reload.profession_summary
  end

  test "Warcraft Logs parses land when a client is available" do
    WarcraftLogsZone.create!(wcl_id: 45, name: "MN Tier 1", expansion_id: 11, closed: false)

    WowCharacterRefreshJob.perform_now(character.id, client: FakeClient.new,
                                       raider_io: FakeRaiderIo.new,
                                       warcraft_logs: FakeWarcraftLogs.new)

    assert_equal 88, character.reload.parse
  end

  # Points-metered and third in line — it must never cost the other two.
  test "a Warcraft Logs failure does not lose the Blizzard or Raider.io data" do
    WarcraftLogsZone.create!(wcl_id: 45, name: "MN Tier 1", expansion_id: 11, closed: false)

    assert_nothing_raised do
      WowCharacterRefreshJob.perform_now(
        character.id, client: FakeClient.new, raider_io: FakeRaiderIo.new,
        warcraft_logs: FakeWarcraftLogs.new(error: WarcraftLogs::Client::RateLimited)
      )
    end

    character.reload
    assert_equal 640, character.average_item_level
    assert_equal "tank", character.role
    assert_empty character.warcraft_logs_rankings
    assert_no_enqueued_jobs only: WowCharacterRefreshJob
  end

  test "a rotated Warcraft Logs token is evicted so the next pass re-mints it" do
    WarcraftLogsZone.create!(wcl_id: 45, name: "MN Tier 1", expansion_id: 11, closed: false)
    evicted = false
    original = WarcraftLogs::Client.method(:expire_access_token)
    WarcraftLogs::Client.define_singleton_method(:expire_access_token) { evicted = true }

    WowCharacterRefreshJob.perform_now(
      character.id, client: FakeClient.new, raider_io: FakeRaiderIo.new,
      warcraft_logs: FakeWarcraftLogs.new(error: WarcraftLogs::Client::Unauthorized)
    )

    assert evicted
  ensure
    WarcraftLogs::Client.define_singleton_method(:expire_access_token, original)
  end

  test "a character Blizzard has lost is not then looked up on Raider.io" do
    asked = false
    rio = Class.new { define_method(:character_profile) { |**| asked = true } }
    blizzard = Class.new do
      def character_profile(*) = raise(BattleNet::Client::NotFound)
      def mythic_keystone_profile(*) = nil
    end

    WowCharacterRefreshJob.perform_now(character.id, client: blizzard.new, raider_io: rio.new)

    assert character.reload.missing?
    assert_not asked, "no point asking Raider.io about a name Blizzard no longer knows"
  end

  # Jobs outlive the rows they reference — an unlink between enqueue and run
  # must be a no-op, not a crash.
  test "a character deleted before the job runs is ignored" do
    id = character.id
    character.destroy!

    assert_nothing_raised { WowCharacterRefreshJob.perform_now(id, client: FakeClient.new) }
  end

  # The cached app token has to be dropped BEFORE the retry, or every attempt
  # replays the same dead token.
  test "an expired app token is evicted from the cache before retrying" do
    evicted = false
    id = character.id

    original_expire = BattleNet::Client.method(:expire_app_token)
    original_call = BattleNet::RefreshCharacter.method(:call)
    BattleNet::Client.define_singleton_method(:expire_app_token) { evicted = true }
    BattleNet::RefreshCharacter.define_singleton_method(:call) { |*, **| raise BattleNet::Client::Unauthorized }

    # retry_on catches the error and reschedules rather than re-raising, so the
    # observable effects are the eviction and the queued retry.
    assert_enqueued_with(job: WowCharacterRefreshJob) { WowCharacterRefreshJob.perform_now(id) }
    assert evicted, "the dead token must be dropped so the retry mints a fresh one"
  ensure
    BattleNet::Client.define_singleton_method(:expire_app_token, original_expire)
    BattleNet::RefreshCharacter.define_singleton_method(:call, original_call)
  end

  test "linking enqueues refreshes so freshly linked characters fill in" do
    auth = OmniAuth::AuthHash.new(uid: "1", info: { battletag: "T#1" },
                                  credentials: { token: "t" }, extra: { raw_info: { "id" => 1 } })

    assert_enqueued_with(job: WowCharacterRefreshJob) do
      BattleNet::LinkAccount.call(user: users(:member), auth: auth,
                                  client_for: ->(_region) { FakeLinkClient.new })
    end
  end

  test "the manual refresh button is not blocked by an expired OAuth grant" do
    character # exists
    account.update!(linked_at: 1.year.ago) # grant long dead

    assert_enqueued_with(job: WowCharacterRefreshJob) do
      account.wow_characters.refreshable(min_level: WowCharacterSweepJob::MIN_LEVEL)
             .pluck(:id).each { |id| WowCharacterRefreshJob.perform_later(id) }
    end
  end
end
