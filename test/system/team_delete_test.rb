require "application_system_test_case"

# The Delete team button stays disabled until the team's name is typed
# (confirm_name_controller.js), then deletes the team.
class TeamDeleteSystemTest < ApplicationSystemTestCase
  setup do
    @guild = Guild.create!(id: 555_000_111_222_333_666, name: "Raid Server")
    ActsAsTenant.with_tenant(@guild) do
      @team = Team.create!(name: "Alpha Team", team_role_id: 1, officer_role_id: 2, review_channel_id: 3)
    end
  end

  # Signs in through the mocked OAuth callback with the remote lookups stubbed,
  # then runs the test body inside the session.
  def signed_in_as_manager
    user = users(:member)
    OmniAuth.config.test_mode = true
    OmniAuth.config.mock_auth[:discord] = OmniAuth::AuthHash.new(
      provider: "discord", uid: user.discord_id.to_s, info: { name: user.username },
      credentials: { token: "test-token" },
      extra: { raw_info: { "username" => user.username, "global_name" => user.global_name } }
    )
    result = Discord::ManageableGuilds::Result.new([ { "id" => @guild.id.to_s } ], [], [ @guild.id.to_s ])
    stub_singleton_method(Discord::ManageableGuilds, :call, result) do
      stub_singleton_method(Discord::Connections, :call, []) do
        visit "/auth/discord/callback"
        yield
      end
    end
  ensure
    OmniAuth.config.mock_auth[:discord] = nil
    OmniAuth.config.test_mode = false
  end

  test "the delete button unlocks only once the team's name is typed" do
    signed_in_as_manager do
      visit guild_team_path(@guild, @team)

      assert_button "Delete team", disabled: true
      fill_in "confirm_name", with: "Alpha"
      assert_button "Delete team", disabled: true
      fill_in "confirm_name", with: "alpha team"
      click_on "Delete team"

      assert_text "Alpha Team was deleted"
      assert_not ActsAsTenant.with_tenant(@guild) { Team.exists?(@team.id) }
    end
  end
end
