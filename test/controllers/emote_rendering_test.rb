require "test_helper"

# Free-typed fields store custom-emote mentions inline (<:name:id>); on the
# web they render as CDN images via discord_emotes, not as literal text.
class EmoteRenderingTest < ActionDispatch::IntegrationTest
  POG = "<:pog:123456789012345678>"
  CDN = "https://cdn.discordapp.com/emojis/123456789012345678.png?size=32"

  setup do
    @guild = Guild.create!(id: 777_000_111_222_333_555, name: "Raid Server",
                           description: "Friendly raiders #{POG}")
    ActsAsTenant.with_tenant(@guild) do
      @team = Team.create!(name: "Alpha", team_role_id: 1, officer_role_id: 2, review_channel_id: 3,
                           description: "We bring #{POG} energy",
                           current_needs: "DPS #{POG}")
    end
  end

  test "the public guild page renders bio, roster lines and guild description emotes as images" do
    get public_guild_path(@guild.slug)

    assert_response :success
    assert_select "img[src=?]", CDN, minimum: 3
    assert_select "img[alt=?]", ":pog:", minimum: 1
    assert_no_match "&lt;:pog:", response.body
    assert_match "We bring", response.body
  end

  test "the dashboard guild page renders team bio emotes as images" do
    sign_in_as users(:member), member: [ @guild ]

    get guild_path(@guild)

    assert_response :success
    assert_select "img[src=?]", CDN, minimum: 1
    assert_no_match "&lt;:pog:", response.body
  end
end
