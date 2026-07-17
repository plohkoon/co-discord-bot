require "test_helper"

class RosterMessageTest < ActiveSupport::TestCase
  SECTION = CoBot::RosterMessage::SECTION
  TEXT_DISPLAY = CoBot::RosterMessage::TEXT_DISPLAY
  SEPARATOR = CoBot::RosterMessage::SEPARATOR
  CONTAINER = CoBot::RosterMessage::CONTAINER

  def guild = @guild ||= Guild.sync_from_discord(id: 1, name: "Test")

  def create_team(name, category: nil, position: 0, **fields)
    ActsAsTenant.with_tenant(guild) do
      Team.create!(name: name, team_role_id: 100, officer_role_id: 200, review_channel_id: 300,
                   team_category: category, position: position, **fields)
    end
  end

  def create_category(name, position:)
    ActsAsTenant.with_tenant(guild) { TeamCategory.create!(name: name, position: position) }
  end

  def add_officer(team, user_id, username)
    ActsAsTenant.with_tenant(guild) do
      TeamOfficer.create!(team: team, discord_user_id: user_id, discord_username: username)
    end
  end

  test "team_block renders the roster lines with leads from the officers mirror" do
    team = create_team("Raiders", team_type: "Heroic Team", progression: "Currently 7/9 H",
                       requirements: "Req. iLvl - 250+", date_and_time: "Tuesdays 7-10pm CT",
                       current_needs: "DPS")
    add_officer(team, 11, "alice")
    add_officer(team, 12, "bob")

    block = ActsAsTenant.with_tenant(guild) { CoBot::RosterMessage.team_block(team) }

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
    block = ActsAsTenant.with_tenant(guild) { CoBot::RosterMessage.team_block(team) }

    assert_equal <<~BLOCK.strip, block
      <@&100>
      __Team Leads:__ —
      __Date and Time:__ —
      __Current Needs:__ —
    BLOCK
  end

  test "grouped orders categories by position, teams by position then name, uncategorized last" do
    pvp = create_category("PvP Teams", position: 2)
    pve = create_category("PvE Teams", position: 1)
    teams = [
      create_team("Zeta", category: pvp),
      create_team("Alpha", category: pve, position: 2),
      create_team("Beta", category: pve, position: 1),
      create_team("Loose")
    ]

    groups = ActsAsTenant.with_tenant(guild) { CoBot::RosterMessage.grouped(teams) }

    assert_equal [ "PvE Teams", "PvP Teams", nil ], groups.map { |category, _| category&.name }
    assert_equal %w[Beta Alpha], groups[0].last.map(&:name)
    assert_equal %w[Loose], groups[2].last.map(&:name)
  end

  test "payloads builds one components-v2 message: headers, role-colored containers, inline apply buttons" do
    pve = create_category("PvE Teams ⚔️", position: 1)
    pvp = create_category("PvP Teams", position: 2)
    alpha = create_team("Alpha", category: pve)
    zeta = create_team("Zeta", category: pvp)
    add_officer(alpha, 11, "alice")

    payloads = ActsAsTenant.with_tenant(guild) do
      CoBot::RosterMessage.payloads([ zeta, alpha ], { "100" => 0xFFD166 })
    end

    assert_equal 1, payloads.size
    payload, included = payloads.first
    assert_equal [ alpha, zeta ], included
    assert_equal CoBot::RosterMessage::FLAG_COMPONENTS_V2, payload["flags"]
    assert_equal({ "parse" => [] }, payload["allowed_mentions"])

    types = payload["components"].map { |c| c["type"] }
    assert_equal [ TEXT_DISPLAY, CONTAINER, SEPARATOR, TEXT_DISPLAY, CONTAINER ], types
    assert_equal "## PvE Teams ⚔️", payload["components"].first["content"]

    container = payload["components"][1]
    assert_equal 0xFFD166, container["accent_color"]
    section = container["components"].first
    assert_equal SECTION, section["type"]
    assert_equal "applyto:#{alpha.id}", section.dig("accessory", "custom_id")
    assert_equal "Apply", section.dig("accessory", "label")
    assert_includes section.dig("components", 0, "content"), "__Team Leads:__ <@11>"
  end

  test "a role without a color renders a borderless container" do
    team = create_team("Plain")
    payloads = ActsAsTenant.with_tenant(guild) do
      CoBot::RosterMessage.payloads([ team ], { "100" => 0 })
    end
    container = payloads.first.first["components"].first
    assert_nil container["accent_color"]
  end

  test "payloads splits into more messages when the component budget overflows" do
    pve = create_category("PvE Teams", position: 1)
    teams = 12.times.map { |i| create_team("Team #{format('%02d', i)}", category: pve) }

    payloads = ActsAsTenant.with_tenant(guild) { CoBot::RosterMessage.payloads(teams) }

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
    add_officer(team, 42, "carol")

    payload = ActsAsTenant.with_tenant(guild) do
      CoBot::RosterMessage.refresh_payload([ team ], { "100" => 0xABCDEF })
    end

    assert_equal CoBot::RosterMessage::FLAG_COMPONENTS_V2, payload["flags"]
    container = payload["components"].find { |c| c["type"] == CONTAINER }
    assert_equal 0xABCDEF, container["accent_color"]
    content = container.dig("components", 0, "components", 0, "content")
    assert_includes content, "__Current Needs:__ Healers"
    assert_includes content, "<@42>"
  end
end
