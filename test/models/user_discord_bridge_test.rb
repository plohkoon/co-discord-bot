require "test_helper"

# The seam between the bot (which knows people only as Discord snowflakes) and
# the web app (which knows them as `users` rows).
#
# The whole point is that a person can own things — a claimed character, say —
# before they have ever visited the website.
class UserDiscordBridgeTest < ActiveSupport::TestCase
  DISCORD_ID = 555_000_111_222_333_444

  def guild = @guild ||= Guild.create!(id: 777_000_111_222_333_444, name: "Raid Server")

  def team
    @team ||= ActsAsTenant.with_tenant(guild) do
      Team.create!(name: "Alpha", team_role_id: 1, officer_role_id: 2, review_channel_id: 3)
    end
  end

  def membership(discord_user_id: DISCORD_ID)
    ActsAsTenant.with_tenant(guild) do
      TeamMembership.create!(team: team, discord_user_id: discord_user_id, discord_username: "applicant")
    end
  end

  # --- Shadow records ---

  test "for_discord creates a person co-bot knows about but who has never signed in" do
    user = User.for_discord(DISCORD_ID, username: "applicant")

    assert_equal DISCORD_ID, user.discord_id
    assert user.shadow?
    assert_not user.authenticated?
    assert_equal "applicant", user.username
  end

  test "for_discord is idempotent" do
    User.for_discord(DISCORD_ID, username: "applicant")
    User.for_discord(DISCORD_ID, username: "applicant")

    assert_equal 1, User.where(discord_id: DISCORD_ID).count
  end

  # The first real sign-in must adopt the shadow row, not fork a second person —
  # otherwise a character claimed while applying would be stranded on a record
  # the user can never reach.
  test "signing in adopts an existing shadow record" do
    shadow = User.for_discord(DISCORD_ID, username: "applicant")
    shadow.wow_characters.create!(blizzard_id: 42, name: "Thrall", realm: "Sargeras",
                                  realm_slug: "sargeras", region: "us", claimed_at: Time.current)

    signed_in = User.from_omniauth(OmniAuth::AuthHash.new(
      provider: "discord", uid: DISCORD_ID.to_s, info: { name: "applicant" },
      extra: { raw_info: { "username" => "applicant", "global_name" => "Applicant" } }
    ))

    assert_equal shadow.id, signed_in.id
    assert signed_in.authenticated?
    assert_equal 1, User.where(discord_id: DISCORD_ID).count
    assert_equal [ "Thrall" ], signed_in.wow_characters.pluck(:name),
                 "the character claimed before signing in is still theirs"
  end

  # A name scraped from an interaction payload must not overwrite one from a
  # real sign-in.
  test "for_discord never downgrades a name set by an actual sign-in" do
    User.from_omniauth(OmniAuth::AuthHash.new(
      provider: "discord", uid: DISCORD_ID.to_s, info: { name: "realname" },
      extra: { raw_info: { "username" => "realname", "global_name" => "Real Name" } }
    ))

    user = User.for_discord(DISCORD_ID, username: "stale-from-interaction")

    assert_equal "realname", user.username
    assert user.authenticated?, "still authenticated"
  end

  # --- The join ---

  test "a membership finds its person by snowflake" do
    user = User.for_discord(DISCORD_ID, username: "applicant")
    record = membership

    assert_equal user, record.user
    assert_equal [ record.id ], user.team_memberships.map(&:id)
  end

  # Nil here means "co-bot has no record of this person", NOT "this person has
  # nothing" — every caller has to read it that way.
  test "a membership for someone unknown has no person, and that is ordinary" do
    record = membership(discord_user_id: 999_888_777_666_555_444)

    assert_nil record.user
  end

  # The person's memberships span every server, which is the question worth
  # asking of a person rather than of a tenant.
  test "memberships are not tenant-scoped when read from the person" do
    user = User.for_discord(DISCORD_ID, username: "applicant")
    other_guild = Guild.create!(id: 888_000_111_222_333_444, name: "Second Server")
    ActsAsTenant.with_tenant(other_guild) do
      other_team = Team.create!(name: "Beta", team_role_id: 4, officer_role_id: 5, review_channel_id: 6)
      TeamMembership.create!(team: other_team, discord_user_id: DISCORD_ID, discord_username: "applicant")
    end
    membership

    assert_equal 2, user.team_memberships.count
  end

  test "an application finds its person the same way" do
    user = User.for_discord(DISCORD_ID, username: "applicant")
    application = ActsAsTenant.with_tenant(guild) do
      TeamApplication.create!(team: team, discord_user_id: DISCORD_ID, discord_username: "applicant")
    end

    assert_equal user, application.user
    assert_equal [ application.id ], user.team_applications.map(&:id)
  end

  # --- What this unlocks ---

  test "a shadow person can own a claimed character" do
    user = User.for_discord(DISCORD_ID, username: "applicant")
    user.wow_characters.create!(blizzard_id: 42, name: "Thrall", realm: "Sargeras",
                                realm_slug: "sargeras", region: "us", claimed_at: Time.current)

    record = membership
    assert_equal [ "Thrall" ], record.user.wow_characters.pluck(:name)
    assert record.user.shadow?, "owning a character proves nothing about identity"
  end
end
