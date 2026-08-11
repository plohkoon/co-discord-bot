require "test_helper"

# Slug behavior on the models: generated at creation, never regenerated on
# rename, unique globally for guilds and per guild for teams.
class SlugTest < ActiveSupport::TestCase
  def create_guild(id:, name:)
    Guild.sync_from_discord(id: id, name: name)
  end

  def create_team(guild, name)
    ActsAsTenant.with_tenant(guild) do
      Team.create!(name: name, team_role_id: 5, officer_role_id: 6, review_channel_id: 7)
    end
  end

  test "a new guild derives its slug from the server name" do
    assert_equal "raid-server", create_guild(id: 1, name: "Raid Server").slug
  end

  test "two guilds with the same name get distinct slugs via an appended word" do
    first = create_guild(id: 1, name: "Raid Server")
    second = create_guild(id: 2, name: "Raid Server")

    assert_equal "raid-server", first.slug
    assert_match(/\Araid-server-[a-z]+\z/, second.slug)
  end

  test "renaming a guild keeps the slug — shared links must not break" do
    guild = create_guild(id: 1, name: "Raid Server")
    Guild.sync_from_discord(id: 1, name: "Totally Rebranded")

    assert_equal "Totally Rebranded", guild.reload.name
    assert_equal "raid-server", guild.slug
  end

  test "team slugs are unique per guild but can repeat across guilds" do
    guild_a = create_guild(id: 1, name: "Server A")
    guild_b = create_guild(id: 2, name: "Server B")

    assert_equal "alpha", create_team(guild_a, "Alpha").slug
    assert_equal "alpha", create_team(guild_b, "Alpha").slug
  end

  test "renaming a team keeps its slug" do
    guild = create_guild(id: 1, name: "Server")
    team = create_team(guild, "Alpha")

    ActsAsTenant.with_tenant(guild) { team.update!(name: "Alpha Reborn") }

    assert_equal "alpha", team.reload.slug
  end

  test "slug format and uniqueness are validated with friendly messages" do
    guild = create_guild(id: 1, name: "Server")
    other = create_guild(id: 2, name: "Other")

    other.slug = "Bad Slug!"
    assert_not other.valid?
    assert_match(/lowercase letters/, other.errors[:slug].to_sentence)

    other.slug = guild.slug
    assert_not other.valid?
    assert_match(/already taken/, other.errors[:slug].to_sentence)

    other.slug = ""
    assert_not other.valid?
  end

  test "an all-emoji team name falls back to the generic base" do
    guild = create_guild(id: 1, name: "Server")

    assert_equal "team", create_team(guild, "🔥🔥").slug
  end
end
