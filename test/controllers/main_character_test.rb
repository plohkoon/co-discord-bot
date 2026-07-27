require "test_helper"

# Nominating a main, and a lead setting which character a member raids as.
class MainCharacterTest < ActionDispatch::IntegrationTest
  NOW = Time.utc(2026, 7, 27)

  def guild = @guild ||= Guild.create!(id: 777_000_111_222_333_444, name: "Raid Server")

  def team
    @team ||= ActsAsTenant.with_tenant(guild) do
      Team.create!(name: "Alpha", team_role_id: 1, officer_role_id: 2, review_channel_id: 3)
    end
  end

  def character(name, owner: users(:member), level: 90)
    owner.wow_characters.create!(
      blizzard_id: name.hash.abs, name: name, realm: "Sargeras", realm_slug: "sargeras",
      region: "us", level: level, claimed_at: NOW
    )
  end

  def membership(user: users(:member))
    ActsAsTenant.with_tenant(guild) do
      TeamMembership.create!(team: team, discord_user_id: user.discord_id,
                             discord_username: user.username, status: :active)
    end
  end

  # --- The person's main ---

  test "a person can nominate their main" do
    alt = character("Alt", level: 40)
    character("Higher", level: 90)
    sign_in_as users(:member)

    post make_main_wow_character_path(alt)

    assert_redirected_to account_path
    assert_equal alt, users(:member).reload.main_wow_character
  end

  test "an explicit choice survives later inference" do
    alt = character("Alt", level: 40)
    sign_in_as users(:member)
    post make_main_wow_character_path(alt)

    character("Higher", level: 90)

    assert_equal alt, users(:member).reload.main_character
  end

  test "one person cannot nominate another's character" do
    theirs = character("Theirs", owner: users(:admin))
    sign_in_as users(:member)

    post make_main_wow_character_path(theirs)

    assert_response :not_found
    assert_nil users(:member).reload.main_wow_character
  end

  test "the account page marks the main and offers to change it" do
    character("Main")
    sign_in_as users(:member)
    users(:member).main_character # inferred

    get account_path

    assert_response :success
    assert_match(/\bmain\b/, response.body)
  end

  # --- The team's active character ---

  test "a lead sets which character a member raids as" do
    record = membership
    thrall = character("Thrall")
    sign_in_as users(:member), manageable: [ guild ]

    patch character_guild_team_membership_path(guild, team, record),
          params: { wow_character_id: thrall.id }

    assert_redirected_to guild_team_membership_path(guild, team, record)
    assert_equal thrall, record.reload.wow_character
  end

  # A lead corrects or swaps a member's character; they do not attribute a
  # stranger's character to them.
  test "a lead cannot attribute someone else's character to a member" do
    record = membership
    theirs = character("Theirs", owner: users(:admin))
    sign_in_as users(:member), manageable: [ guild ]

    patch character_guild_team_membership_path(guild, team, record),
          params: { wow_character_id: theirs.id }

    assert_nil record.reload.wow_character, "not theirs to assign"
  end

  test "clearing the active character is allowed" do
    record = membership
    thrall = character("Thrall")
    record.update!(wow_character: thrall)
    sign_in_as users(:member), manageable: [ guild ]

    patch character_guild_team_membership_path(guild, team, record), params: { wow_character_id: "" }

    assert_nil record.reload.wow_character
  end

  # nil user is the common case — a member who never signed in has no record.
  test "setting a character on a member co-bot has no record of is a no-op, not a crash" do
    record = ActsAsTenant.with_tenant(guild) do
      TeamMembership.create!(team: team, discord_user_id: 999_888_777_666, discord_username: "stranger")
    end
    thrall = character("Thrall")
    sign_in_as users(:member), manageable: [ guild ]

    patch character_guild_team_membership_path(guild, team, record),
          params: { wow_character_id: thrall.id }

    assert_nil record.reload.wow_character
  end

  test "someone without team access cannot set a member's character" do
    record = membership
    thrall = character("Thrall")
    sign_in_as users(:admin), member: [ guild ]

    patch character_guild_team_membership_path(guild, team, record),
          params: { wow_character_id: thrall.id }

    assert_nil record.reload.wow_character
  end
end
