require "test_helper"

# Web accept/reject/remove — the officer powers, exercised as a team lead.
# Role changes go through Memberships::RestRoleManager, stubbed here (no HTTP).
class ApplicationDecisionsTest < ActionDispatch::IntegrationTest
  setup do
    @guild = Guild.create!(id: 777_000_111_222_333_444, name: "Raid Server")
    ActsAsTenant.with_tenant(@guild) do
      @team = Team.create!(name: "Alpha", team_role_id: 1, officer_role_id: 2, review_channel_id: 3)
      @membership = TeamMembership.create!(team: @team, discord_user_id: 42, discord_username: "recruit", status: :pending)
      @application = TeamApplication.create!(team: @team, team_membership: @membership,
                                             discord_user_id: 42, discord_username: "recruit",
                                             status: :pending, source: :applied)
      TeamOfficer.create!(team: @team, discord_user_id: users(:member).discord_id, discord_username: users(:member).username)
    end
    sign_in_as users(:member), member: [ @guild ]
  end

  def accept_path = accept_guild_team_membership_application_path(@guild, @team, @membership, @application)
  def reject_path = reject_guild_team_membership_application_path(@guild, @team, @membership, @application)

  test "a lead can accept: role granted, membership activated, decider recorded" do
    granted = []
    stub_singleton_method(Memberships::RestRoleManager, :grant, ->(**kwargs) { granted << kwargs }) do
      post accept_path
    end

    assert_redirected_to guild_team_membership_path(@guild, @team, @membership)
    assert_equal [ { team: @team, discord_user_id: 42 } ], granted
    assert @application.reload.accepted?
    assert_equal users(:member).discord_id, @application.decided_by_discord_id
    assert @membership.reload.active?
  end

  test "a lead can reject: membership archived, no role call" do
    post reject_path

    assert_redirected_to guild_team_membership_path(@guild, @team, @membership)
    assert @application.reload.rejected?
    assert @membership.reload.archived?
  end

  test "a failed role grant reverts the application to pending" do
    boom = ->(**) { raise Memberships::RoleError, "the bot needs Manage Roles" }
    stub_singleton_method(Memberships::RestRoleManager, :grant, boom) do
      post accept_path
    end

    assert_redirected_to guild_team_membership_path(@guild, @team, @membership)
    assert_match(/Manage Roles/, flash[:alert])
    assert @application.reload.pending?
    assert @membership.reload.pending?
  end

  test "deciding an already-decided application is a no-op" do
    ActsAsTenant.with_tenant(@guild) { @application.update!(status: :rejected, decided_at: Time.current) }

    post accept_path
    assert_match(/already handled/, flash[:alert])
    assert @application.reload.rejected?
  end

  test "plain members can't decide" do
    ActsAsTenant.with_tenant(@guild) { TeamOfficer.delete_all }

    post accept_path
    assert_redirected_to guild_path(@guild)
    assert @application.reload.pending?
  end

  test "a lead can remove an active member: role revoked, membership archived" do
    ActsAsTenant.with_tenant(@guild) { @membership.update!(status: :active) }

    revoked = []
    stub_singleton_method(Memberships::RestRoleManager, :revoke, ->(**kwargs) { revoked << kwargs }) do
      post remove_guild_team_membership_path(@guild, @team, @membership)
    end

    assert_redirected_to guild_team_path(@guild, @team)
    assert_equal [ { team: @team, discord_user_id: 42 } ], revoked
    assert @membership.reload.archived?
  end

  test "a failed role revoke keeps the membership intact" do
    ActsAsTenant.with_tenant(@guild) { @membership.update!(status: :active) }

    boom = ->(**) { raise Memberships::RoleError, "role order" }
    stub_singleton_method(Memberships::RestRoleManager, :revoke, boom) do
      post remove_guild_team_membership_path(@guild, @team, @membership)
    end

    assert_match(/role order/, flash[:alert])
    assert @membership.reload.active?
  end

  test "plain members can't remove" do
    ActsAsTenant.with_tenant(@guild) { TeamOfficer.delete_all }

    post remove_guild_team_membership_path(@guild, @team, @membership)
    assert_redirected_to guild_path(@guild)
    assert @membership.reload.pending?
  end
end
