require "test_helper"

class RosterMessageTest < ActiveSupport::TestCase
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

  test "apply_view carries the applyto custom id for the team" do
    team = create_team("Raiders")
    row = CoBot::RosterMessage.apply_view(team).to_a.first
    button = row[:components].first
    assert_equal "applyto:#{team.id}", button[:custom_id]
    assert_equal "Apply — Raiders", button[:label]
  end
end
