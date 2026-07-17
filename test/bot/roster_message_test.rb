require "test_helper"

class RosterMessageTest < ActiveSupport::TestCase
  SECTION = CoBot::RosterMessage::SECTION
  TEXT_DISPLAY = CoBot::RosterMessage::TEXT_DISPLAY
  SEPARATOR = CoBot::RosterMessage::SEPARATOR

  def guild = @guild ||= Guild.sync_from_discord(id: 1, name: "Test")

  def create_team(name, category: nil, **fields)
    ActsAsTenant.with_tenant(guild) do
      Team.create!(name: name, team_role_id: 100, officer_role_id: 200, review_channel_id: 300,
                   team_category: category, **fields)
    end
  end

  def create_category(name, position:)
    ActsAsTenant.with_tenant(guild) { TeamCategory.create!(name: name, position: position) }
  end

  test "team_block renders the roster lines with leads and skips blank summary parts" do
    team = create_team("Raiders", team_type: "Heroic Team", progression: "Currently 7/9 H",
                       requirements: "Req. iLvl - 250+", date_and_time: "Tuesdays 7-10pm CT",
                       current_needs: "DPS")

    block = CoBot::RosterMessage.team_block(team, [ 11, 12 ])

    assert_equal <<~BLOCK.strip, block
      <@&100>
      *Heroic Team* | Currently 7/9 H | Req. iLvl - 250+
      __Team Leads:__ <@11> | <@12>
      __Date and Time:__ Tuesdays 7-10pm CT
      __Current Needs:__ DPS
    BLOCK
  end

  test "team_block with no details shows placeholder dashes and no summary line" do
    team = create_team("Bare")
    block = CoBot::RosterMessage.team_block(team, [])

    assert_equal <<~BLOCK.strip, block
      <@&100>
      __Team Leads:__ —
      __Date and Time:__ —
      __Current Needs:__ —
    BLOCK
  end

  test "grouped orders categories by position and puts uncategorized teams last" do
    pvp = create_category("PvP Teams", position: 2)
    pve = create_category("PvE Teams", position: 1)
    teams = [
      create_team("Zeta", category: pvp),
      create_team("Alpha", category: pve),
      create_team("Beta", category: pve),
      create_team("Loose")
    ]

    groups = CoBot::RosterMessage.grouped(teams)

    assert_equal [ "PvE Teams", "PvP Teams", nil ], groups.map { |category, _| category&.name }
    assert_equal %w[Alpha Beta], groups[0].last.map(&:name)
    assert_equal %w[Loose], groups[2].last.map(&:name)
  end

  test "payloads builds one components-v2 message with headers, sections, and inline apply buttons" do
    pve = create_category("PvE Teams ⚔️", position: 1)
    pvp = create_category("PvP Teams", position: 2)
    alpha = create_team("Alpha", category: pve)
    zeta = create_team("Zeta", category: pvp)

    payloads = CoBot::RosterMessage.payloads([ zeta, alpha ], { alpha.id => [ 11 ], zeta.id => [] })

    assert_equal 1, payloads.size
    payload, included = payloads.first
    assert_equal [ alpha, zeta ], included
    assert_equal CoBot::RosterMessage::FLAG_COMPONENTS_V2, payload["flags"]
    assert_equal({ "parse" => [] }, payload["allowed_mentions"])

    types = payload["components"].map { |c| c["type"] }
    assert_equal [ TEXT_DISPLAY, SECTION, SEPARATOR, TEXT_DISPLAY, SECTION ], types

    header = payload["components"].first
    assert_equal "## PvE Teams ⚔️", header["content"]

    section = payload["components"][1]
    assert_equal "applyto:#{alpha.id}", section.dig("accessory", "custom_id")
    assert_equal "Apply", section.dig("accessory", "label")
    assert_includes section.dig("components", 0, "content"), "__Team Leads:__ <@11>"
  end

  test "payloads splits into more messages when the component budget overflows" do
    pve = create_category("PvE Teams", position: 1)
    teams = 16.times.map { |i| create_team("Team #{format('%02d', i)}", category: pve) }

    payloads = CoBot::RosterMessage.payloads(teams, {})

    assert_operator payloads.size, :>, 1
    assert_equal teams.map(&:name).sort, payloads.flat_map { |_, included| included.map(&:name) }.sort
    payloads.each do |payload, _|
      assert_operator CoBot::RosterMessage.component_cost(payload["components"]), :<=, CoBot::RosterMessage::MAX_COMPONENTS
      # every message re-states the category header for context
      assert_equal "## PvE Teams", payload["components"].first["content"]
    end
  end

  test "refresh_payload rebuilds a single message for the given teams" do
    pve = create_category("PvE Teams", position: 1)
    team = create_team("Alpha", category: pve, current_needs: "Healers")

    payload = CoBot::RosterMessage.refresh_payload([ team ], { team.id => [ 42 ] })

    assert_equal CoBot::RosterMessage::FLAG_COMPONENTS_V2, payload["flags"]
    section = payload["components"].find { |c| c["type"] == SECTION }
    assert_includes section.dig("components", 0, "content"), "__Current Needs:__ Healers"
    assert_includes section.dig("components", 0, "content"), "<@42>"
  end
end
