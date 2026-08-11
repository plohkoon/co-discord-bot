require "test_helper"

# The web side of connecting a WoW account: what sign-in learns from Discord,
# and the Battle.net link/unlink flow on /account.
class BattleNetLinkTest < ActionDispatch::IntegrationTest
  def battle_net_connection(id: "123456789", name: "Thrall#1234", verified: true)
    discord_connection(type: "battlenet", id: id, name: name, verified: verified)
  end

  def create_account(user, battle_net_id: 123_456_789, battle_tag: "Thrall#1234")
    user.battle_net_accounts.create!(
      battle_net_id: battle_net_id, battle_tag: battle_tag,
      region: "us", linked_at: Time.current, characters_synced_at: Time.current
    )
  end

  # --- What sign-in captures from Discord ---

  test "sign-in records the Battle.net account Discord already knows about" do
    sign_in_as users(:member), connections: [ battle_net_connection ]

    user = users(:member).reload
    assert_equal "123456789", user.discord_battle_net_id
    assert_equal "Thrall#1234", user.discord_battle_tag
    assert user.battle_net_link_suggested?
  end

  test "sign-in ignores unverified and unrelated connections" do
    sign_in_as users(:member), connections: [
      discord_connection(type: "steam", id: "1", name: "thrall"),
      battle_net_connection(verified: false)
    ]

    assert_nil users(:member).reload.discord_battle_tag
  end

  test "unlinking on Discord's side clears what we recorded" do
    users(:member).update!(discord_battle_net_id: "1", discord_battle_tag: "Old#1")

    sign_in_as users(:member), connections: []

    assert_nil users(:member).reload.discord_battle_tag
  end

  test "sign-in still succeeds when the connections call comes back empty" do
    sign_in_as users(:member), connections: []

    assert_redirected_to root_path
  end

  # --- The account page ---

  test "the account page suggests linking when Discord reports a Battle.net account" do
    sign_in_as users(:member), connections: [ battle_net_connection ]

    get account_path

    assert_response :success
    assert_match "Thrall#1234", response.body
  end

  test "the account page lists linked characters" do
    account = create_account(users(:member))
    account.wow_characters.create!(blizzard_id: 1, name: "Thrall", realm: "Illidan",
                                   realm_slug: "illidan", level: 80,
                                   playable_class: "Shaman", verified_at: Time.current)
    sign_in_as users(:member)

    get account_path

    assert_response :success
    assert_match "Thrall-Illidan", response.body
  end

  test "the account page flags a Battle.net link that disagrees with Discord" do
    users(:member).update!(discord_battle_net_id: "999", discord_battle_tag: "Someone#9999")
    create_account(users(:member))
    sign_in_as users(:member), connections: [ battle_net_connection(id: "999", name: "Someone#9999") ]

    get account_path

    assert_match "different Battle.net account", response.body
  end

  test "signing out of the account page is required" do
    get account_path

    assert_redirected_to login_path(return_to: account_path)
  end

  # --- The OAuth callback ---

  test "a successful callback links the account" do
    sign_in_as users(:member)
    account = create_account(users(:member))
    character = account.wow_characters.create!(blizzard_id: 1, name: "Thrall", realm: "Illidan",
                                               realm_slug: "illidan", verified_at: Time.current)

    link_battle_net(uid: 123_456_789, battletag: "Thrall#1234",
                    link: BattleNet::LinkAccount::Result.new(account: account, characters: [ character ]))

    assert_redirected_to account_path
    assert_match(/1 character verified/, flash[:notice])
  end

  test "a failed link reports the reason instead of pretending it worked" do
    sign_in_as users(:member)

    link_battle_net(uid: 1, battletag: "A#1",
                    link: BattleNet::LinkAccount::Result.new(account: nil, characters: [],
                                                             error: "Blizzard said no."))

    assert_redirected_to account_path
    assert_equal "Blizzard said no.", flash[:alert]
  end

  # A failed *link* must not dump an already signed-in user back at the login
  # page as though their session died — OmniAuth's on_failure hook branches on
  # the strategy to keep the two apart.
  test "a cancelled Battle.net link lands back on the account page" do
    sign_in_as users(:member)

    OmniAuth.config.test_mode = true
    OmniAuth.config.mock_auth[:battle_net] = :access_denied
    post "/auth/battle_net"
    follow_redirect!

    assert_redirected_to account_path
    assert_match(/cancelled or failed/i, flash[:alert])
  ensure
    OmniAuth.config.mock_auth[:battle_net] = nil
    OmniAuth.config.test_mode = false
  end

  test "a failed Discord sign-in still goes to the login page" do
    get "/auth/failure", params: { message: "access_denied", strategy: "discord" }

    assert_redirected_to login_path
  end

  # --- Unlinking ---

  test "unlinking removes the account and its characters" do
    account = create_account(users(:member))
    account.wow_characters.create!(blizzard_id: 1, name: "Thrall", realm: "Illidan",
                                   realm_slug: "illidan", verified_at: Time.current)
    sign_in_as users(:member)

    delete battle_net_account_path(account)

    assert_redirected_to account_path
    assert_equal 0, BattleNetAccount.count
    assert_equal 0, WowCharacter.count
  end

  test "a user cannot unlink someone else's Battle.net account" do
    account = create_account(users(:admin))
    sign_in_as users(:member)

    delete battle_net_account_path(account)

    assert_response :not_found
    assert_equal 1, BattleNetAccount.count
  end
end
