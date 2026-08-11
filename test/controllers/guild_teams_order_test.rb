require "test_helper"

# The guild dashboard lists teams recruiting-first — closed teams sink to the
# bottom, with the position order kept within each group (mirroring the
# Discord roster and /team list).
class GuildTeamsOrderTest < ActionDispatch::IntegrationTest
  setup do
    @guild = Guild.create!(id: 777_000_111_222_333_444, name: "Raid Server")
    ActsAsTenant.with_tenant(@guild) do
      [ [ "Closed Early", 1, false ], [ "Open Late", 3, true ],
        [ "Closed Late", 4, false ], [ "Open Early", 2, true ] ].each_with_index do |(name, position, recruiting), i|
        Team.create!(name: name, team_role_id: 10 + i, officer_role_id: 20 + i, review_channel_id: 30 + i,
                     position: position, recruiting: recruiting)
      end
    end
  end

  test "the guild page lists recruiting teams first, position order within each group" do
    sign_in_as users(:member), member: [ @guild ]

    get guild_path(@guild)
    assert_response :success

    offsets = [ "Open Early", "Open Late", "Closed Early", "Closed Late" ].map { |name| response.body.index(name) }
    assert offsets.all?, "expected every team on the page, got offsets #{offsets.inspect}"
    assert_equal offsets.sort, offsets, "teams rendered out of order"
  end
end
