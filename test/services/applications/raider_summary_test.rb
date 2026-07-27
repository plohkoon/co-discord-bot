require "test_helper"

module Applications
  # The four states matter more than the formatting: three of them look like
  # "no data" if you're careless, and an officer reading "no parses" about
  # someone who has a 99 is worse than showing nothing at all.
  class RaiderSummaryTest < ActiveSupport::TestCase
    NOW = Time.utc(2026, 7, 27)

    def guild = @guild ||= Guild.create!(id: 777_000_111_222_333_444, name: "Raid Server")

    def team
      @team ||= ActsAsTenant.with_tenant(guild) do
        Team.create!(name: "Alpha", team_role_id: 1, officer_role_id: 2, review_channel_id: 3)
      end
    end

    # `resolved:` defaults to true because most tests are about what a
    # *settled* application shows; the pending case is called out explicitly.
    def application(input: "Thrall-Sargeras", character: nil, resolved: true)
      # A distinct applicant each time: one pending application per person per
      # team is enforced by a partial unique index.
      @applicant = (@applicant || 900_000_000_000_000) + 1
      ActsAsTenant.with_tenant(guild) do
        TeamApplication.create!(team: team, discord_user_id: @applicant,
                                discord_username: "applicant",
                                character_input: input, wow_character: character,
                                character_resolved_at: (NOW if resolved))
      end
    end

    def character(refreshed: true, verified: false, **overrides)
      @seq = (@seq || 0) + 1
      users(:member).wow_characters.create!({
        blizzard_id: 42 + @seq, name: "Thrall", realm: "Sargeras", realm_slug: "sargeras",
        region: "us", level: 90, playable_class: "Shaman", active_spec: "Enhancement",
        average_item_level: 641, claimed_at: NOW,
        verified_at: (NOW if verified), refreshed_at: (NOW if refreshed)
      }.merge(overrides))
    end

    # --- The four states ---

    test "a team that doesn't ask for a character shows nothing" do
      summary = RaiderSummary.call(application(input: nil))

      assert_equal :not_asked, summary.state
      assert_not summary.show?
      assert_nil RaiderSummary.body(application(input: nil))
    end

    # The ambiguous window is every application's first seconds: resolution is
    # asynchronous, so "haven't looked yet" must not read as "no such character".
    test "a named character not yet looked up reads as loading, not as a typo" do
      app = application(resolved: false)

      assert_equal :loading, RaiderSummary.call(app).state
      assert_match(/loading/i, RaiderSummary.body(app))
      assert_no_match(/cannot load/i, RaiderSummary.body(app))
    end

    # A character row exists the moment it's claimed, before any of the four
    # services have been asked.
    test "a resolved character with no data yet is still loading" do
      app = application(character: character(refreshed: false))

      assert_equal :loading, RaiderSummary.call(app).state
      assert_match(/loading/i, RaiderSummary.body(app))
    end

    test "an unrecognised character says so and quotes what they typed" do
      app = application(input: "Thral-Sargeras", resolved: true)

      assert_equal :failed, RaiderSummary.call(app).state
      body = RaiderSummary.body(app)
      assert_match(/cannot load raider data/i, body)
      assert_match(/Thral-Sargeras/, body)
    end

    test "a gathered character reports its numbers" do
      app = application(character: character)

      summary = RaiderSummary.call(app)
      assert summary.ready?
      body = RaiderSummary.body(app)
      assert_match(/Thrall-Sargeras/, body)
      assert_match(/ilvl 641/, body)
    end

    # --- What it reports ---

    test "an unverified character is marked as a claim, not stated as fact" do
      assert_match(/unverified/i, RaiderSummary.body(application(character: character)))
      assert_no_match(/unverified/i, RaiderSummary.body(application(character: character(verified: true))))
    end

    test "reports parse, M+, raid progression and best credential" do
      char = character
      WarcraftLogsZone.create!(wcl_id: 46, name: "VS / DR / MQD", expansion_id: 11, closed: false)
      char.warcraft_logs_rankings.create!(wcl_zone_id: 46, difficulty: 5, total_kills: 143,
                                          median_performance_average: 84.7, fetched_at: NOW)
      char.update!(raider_io_score: 2903.6, raider_io_role: "tank")
      char.wow_character_raids.create!(raid_slug: "tier-mn-1", summary: "1/9 M",
                                       mythic_bosses_killed: 1, fetched_at: NOW)
      char.wow_character_achievements.create!(blizzard_id: 1, name: "Cutting Edge: Chimaerus",
                                              category: "cutting_edge", completed_at: Time.utc(2026, 5, 1))

      body = RaiderSummary.body(application(character: char))
      assert_match(/Parse.*85 Mythic \(143 kills\)/, body)
      assert_match(/M\+.*2904.*TANK/, body)
      assert_match(%r{Raid.*1/9 M}, body)
      assert_match(/Cutting Edge: Chimaerus \(May 2026\)/, body)
    end

    # Peak only earns its space when it says something the current score doesn't
    # — a fallen-off raider reads very differently from a rising one.
    test "peak score is shown only when it beats the current one" do
      char = character
      char.update!(raider_io_score: 2000.0)
      WowSeason.create!(slug: "season-tww-3", ranked: true, starts_at: 2.years.ago, ends_at: 1.year.ago)
      char.wow_character_seasons.create!(season_slug: "season-tww-3", score_all: 3055, fetched_at: NOW)

      assert_match(/peak 3055/, RaiderSummary.body(application(character: char)))

      char.update!(raider_io_score: 3200.0)
      assert_no_match(/peak/, RaiderSummary.body(application(character: char.reload)))
    end

    test "a character with nothing gathered still reports its identity" do
      body = RaiderSummary.body(application(character: character))

      assert_match(/Thrall-Sargeras/, body)
      assert_no_match(/Parse/, body)
    end
  end
end
