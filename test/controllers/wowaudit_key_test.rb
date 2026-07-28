require "test_helper"

# A stored third-party credential should never be rendered back into the page,
# which means a blank field has to mean "leave it alone" rather than "clear it".
class WowauditKeyTest < ActionDispatch::IntegrationTest
  setup do
    @guild = Guild.create!(id: 555_000_111_222_333_444, name: "Raid Server")
    @team = ActsAsTenant.with_tenant(@guild) do
      Team.create!(name: "Alpha", team_role_id: 1, officer_role_id: 2, review_channel_id: 3,
                   wowaudit_api_key: "existing-key")
    end
  end

  test "the stored key is never rendered into the page" do
    sign_in_as users(:member), manageable: [ @guild ]

    get guild_team_path(@guild, @team)

    assert_response :success
    assert_no_match(/existing-key/, response.body)
    assert_match(/Saved — type a new key/, response.body)
  end

  test "saving the form with a blank key leaves it alone" do
    sign_in_as users(:member), manageable: [ @guild ]

    patch guild_team_path(@guild, @team), params: { team: { name: "Alpha", wowaudit_api_key: "" } }

    assert_equal "existing-key", @team.reload.wowaudit_api_key
  end

  # Removing a credential should take a deliberate act, not an empty field.
  test "disconnecting explicitly does clear it" do
    sign_in_as users(:member), manageable: [ @guild ]

    patch guild_team_path(@guild, @team),
          params: { team: { wowaudit_api_key: "" }, clear_wowaudit: true }

    assert_nil @team.reload.wowaudit_api_key.presence
  end

  test "a lead without Manage Server cannot set the key" do
    ActsAsTenant.with_tenant(@guild) do
      TeamOfficer.create!(team: @team, discord_user_id: users(:member).discord_id,
                          discord_username: users(:member).username)
    end
    sign_in_as users(:member), member: [ @guild ]

    patch guild_team_path(@guild, @team), params: { team: { wowaudit_api_key: "theirs" } }

    assert_equal "existing-key", @team.reload.wowaudit_api_key
  end
end
