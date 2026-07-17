require "test_helper"

# Web access tiers: members of a server can view it; a team page opens only
# for Manage Server holders or that team's leads (team_officers mirror);
# team settings (roster details, questions) stay Manage Server-only.
class GuildAccessTest < ActionDispatch::IntegrationTest
  setup do
    @guild = Guild.create!(id: 555_000_111_222_333_444, name: "Raid Server")
    ActsAsTenant.with_tenant(@guild) do
      @team       = Team.create!(name: "Alpha", team_role_id: 1, officer_role_id: 2, review_channel_id: 3)
      @other_team = Team.create!(name: "Bravo", team_role_id: 4, officer_role_id: 5, review_channel_id: 6)
      @membership = TeamMembership.create!(team: @team, discord_user_id: 42, discord_username: "recruit", status: :active)
    end
  end

  def make_lead!(user, team = @team)
    ActsAsTenant.with_tenant(@guild) do
      TeamOfficer.create!(team: team, discord_user_id: user.discord_id, discord_username: user.username)
    end
  end

  test "strangers can't view a server" do
    sign_in_as users(:member)

    get guild_path(@guild)
    assert_redirected_to root_path
  end

  test "members can view the server but not open teams" do
    sign_in_as users(:member), member: [ @guild ]

    get guild_path(@guild)
    assert_response :success
    assert_select "a", text: "New team", count: 0
    assert_select "a[href=?]", guild_team_path(@guild, @team), count: 0

    get guild_team_path(@guild, @team)
    assert_redirected_to guild_path(@guild)
  end

  test "team leads can open their team, but only theirs" do
    make_lead!(users(:member))
    sign_in_as users(:member), member: [ @guild ]

    get guild_path(@guild)
    assert_select "a[href=?]", guild_team_path(@guild, @team)

    get guild_team_path(@guild, @team)
    assert_response :success
    # Admin-only sections stay hidden from leads.
    assert_select "h2", text: /Team details/, count: 0
    assert_select "h2", text: /Application questions/, count: 0

    get guild_team_path(@guild, @other_team)
    assert_redirected_to guild_path(@guild)
  end

  test "team leads can't edit roster details or questions" do
    make_lead!(users(:member))
    sign_in_as users(:member), member: [ @guild ]

    patch guild_team_path(@guild, @team), params: { team: { position: 5 } }
    assert_redirected_to guild_path(@guild)

    post guild_team_questions_path(@guild, @team), params: { application_question: { label: "Hi" } }
    assert_redirected_to guild_path(@guild)
  end

  test "team leads can view memberships and add notes" do
    make_lead!(users(:member))
    sign_in_as users(:member), member: [ @guild ]

    get guild_team_membership_path(@guild, @team, @membership)
    assert_response :success

    assert_difference -> { MembershipNote.where(team_membership_id: @membership.id).count } do
      post guild_team_membership_notes_path(@guild, @team, @membership),
           params: { membership_note: { body: "solid tank" } }
    end
    assert_redirected_to guild_team_membership_path(@guild, @team, @membership)
  end

  test "plain members can't view memberships or add notes" do
    sign_in_as users(:member), member: [ @guild ]

    get guild_team_membership_path(@guild, @team, @membership)
    assert_redirected_to guild_path(@guild)

    assert_no_difference -> { MembershipNote.count } do
      post guild_team_membership_notes_path(@guild, @team, @membership),
           params: { membership_note: { body: "sneaky" } }
    end
  end

  test "the officers mirror grants view access even when the session predates it" do
    make_lead!(users(:member))
    sign_in_as users(:member) # no membership captured at login

    get guild_path(@guild)
    assert_response :success

    get guild_team_path(@guild, @team)
    assert_response :success
  end

  test "managers can still edit teams" do
    sign_in_as users(:member), manageable: [ @guild ]

    patch guild_team_path(@guild, @team), params: { team: { position: 5 } }
    assert_redirected_to guild_team_path(@guild, @team)
    assert_equal 5, @team.reload.position
  end

  test "the dashboard lists member servers separately" do
    sign_in_as users(:member), member: [ @guild ]

    get root_path
    assert_response :success
    assert_select "div", text: "Servers you're in"
    assert_select "a[href=?]", guild_path(@guild.id), text: /Raid Server/
  end
end
