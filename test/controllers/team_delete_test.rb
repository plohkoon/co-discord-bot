require "test_helper"

# Deleting a team from its web page: Manage Server only, and only with the
# team's name typed as confirmation.
class TeamDeleteTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    @guild = Guild.create!(id: 777_000_111_222_333_666, name: "Raid Server")
    @team = ActsAsTenant.with_tenant(@guild) do
      Team.create!(name: "Alpha Team", team_role_id: 1, officer_role_id: 2, review_channel_id: 3)
    end
  end

  def team_exists? = ActsAsTenant.with_tenant(@guild) { Team.exists?(@team.id) }

  def make_lead
    ActsAsTenant.with_tenant(@guild) do
      TeamOfficer.create!(team: @team, discord_user_id: users(:member).discord_id, discord_username: users(:member).username)
    end
  end

  test "a manager sees the delete section; a lead doesn't" do
    sign_in_as users(:member), manageable: [ @guild ]
    get guild_team_path(@guild, @team)
    assert_select "form[action=?] input[name=confirm_name]", guild_team_path(@guild, @team)

    make_lead
    sign_in_as users(:member), member: [ @guild ]
    get guild_team_path(@guild, @team)
    assert_response :success
    assert_select "input[name=confirm_name]", count: 0
  end

  test "a manager who types the name deletes the team and queues the role removal" do
    sign_in_as users(:member), manageable: [ @guild ]

    delete guild_team_path(@guild, @team), params: { confirm_name: "  alpha team " }

    assert_redirected_to guild_path(@guild)
    assert_match(/Alpha Team was deleted/, flash[:notice])
    assert_not team_exists?
    assert_enqueued_with(job: TeamRoleStripJob, args: [ { guild_id: @guild.id, role_id: 1, team_name: "Alpha Team" } ])
  end

  test "the wrong name deletes nothing" do
    sign_in_as users(:member), manageable: [ @guild ]

    delete guild_team_path(@guild, @team), params: { confirm_name: "Alpha" }

    assert_redirected_to guild_team_path(@guild, @team)
    assert_match(/Type the team's name/, flash[:alert])
    assert team_exists?
    assert_no_enqueued_jobs(only: TeamRoleStripJob)
  end

  test "a lead can't delete their own team, even with the name" do
    make_lead
    sign_in_as users(:member), member: [ @guild ]

    delete guild_team_path(@guild, @team), params: { confirm_name: "Alpha Team" }

    assert_redirected_to guild_path(@guild)
    assert_match(/Manage Server/, flash[:alert])
    assert team_exists?
  end
end
