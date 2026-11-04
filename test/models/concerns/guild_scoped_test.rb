require "test_helper"

# acts_as_tenant 2.x validates belongs_to associations on save. GuildScoped
# keeps that check between guild-scoped models and skips it for associations
# into per-person models (User, WowCharacter), which have no guild.
class GuildScopedTest < ActiveSupport::TestCase
  def guild = @guild ||= Guild.create!(id: 555_000_111_222_333_444, name: "Raid Server")
  def other_guild = @other_guild ||= Guild.create!(id: 666_000_111_222_333_444, name: "Other Server")

  def team = @team ||= ActsAsTenant.with_tenant(guild) do
    Team.create!(name: "Alpha", team_role_id: 1, officer_role_id: 2, review_channel_id: 3)
  end

  test "a membership saves for a Discord user who has never signed into the web app" do
    assert_nil User.find_by(discord_id: 123_456_789)

    membership = ActsAsTenant.with_tenant(guild) do
      TeamMembership.create!(team: team, discord_user_id: 123_456_789, discord_username: "lurker")
    end

    assert membership.persisted?
    assert_nil membership.user
  end

  test "a membership can point at a character owned by someone, whichever guild they're in" do
    user = User.create!(discord_id: 987_654_321, username: "thrall")
    character = WowCharacter.create!(user: user, blizzard_id: 42, name: "Thrall", realm_slug: "sargeras",
                                     realm: "Sargeras", region: "us", claimed_at: Time.current)

    membership = ActsAsTenant.with_tenant(guild) do
      TeamMembership.create!(team: team, discord_user_id: user.discord_id, discord_username: "thrall",
                             wow_character: character)
    end

    assert_equal character, membership.reload.wow_character
  end

  test "a guild-scoped association still can't reach into another guild" do
    theirs = ActsAsTenant.with_tenant(other_guild) { TeamCategory.create!(name: "Theirs") }

    error = assert_raises(ActiveRecord::RecordInvalid) do
      ActsAsTenant.with_tenant(guild) { team.update!(team_category_id: theirs.id) }
    end
    assert_match(/Team category association is invalid/, error.message)
  end
end
