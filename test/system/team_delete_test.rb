require "application_system_test_case"

# The Delete team button stays disabled until the team's name is typed
# (confirm_name_controller.js), then asks once more before deleting.
class TeamDeleteSystemTest < ApplicationSystemTestCase
  setup do
    @guild = Guild.create!(id: 555_000_111_222_333_666, name: "Raid Server")
    ActsAsTenant.with_tenant(@guild) do
      @team = Team.create!(name: "Alpha Team", team_role_id: 1, officer_role_id: 2, review_channel_id: 3)
    end
  end

  # Stands in for Discord::BotApi so the server page a delete redirects to
  # never makes real calls — dotenv loads a developer's .env, bot token and
  # all, into the test env. Unconfigured, and every call fails like an outage,
  # which those pages already handle.
  class OfflineApi
    def configured? = false
    def method_missing(*) = raise(Discord::BotApi::Error, "offline in tests")
    def respond_to_missing?(*) = true
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
        stub_singleton_method(Discord::BotApi, :new, OfflineApi.new) do
          visit "/auth/discord/callback"
          yield
        end
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
      message = accept_confirm { click_on "Delete team" }

      assert_match(/Delete Alpha Team\?/, message)
      assert_text "Alpha Team was deleted"
      assert_not ActsAsTenant.with_tenant(@guild) { Team.exists?(@team.id) }
    end
  end

  test "cancelling the confirmation deletes nothing" do
    signed_in_as_manager do
      visit guild_team_path(@guild, @team)
      # Disabled means the page's JS is running — clicking before it is would
      # submit with no dialog at all.
      assert_button "Delete team", disabled: true

      fill_in "confirm_name", with: "Alpha Team"
      dismiss_confirm { click_on "Delete team" }

      assert_current_path guild_team_path(@guild, @team)
      assert ActsAsTenant.with_tenant(@guild) { Team.exists?(@team.id) }
    end
  end
end
