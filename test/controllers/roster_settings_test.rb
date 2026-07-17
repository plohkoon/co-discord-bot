require "test_helper"

# The curated roster lists (categories + team types) and team renames: Manage
# Server only, and every change that a posted roster shows enqueues a refresh.
class RosterSettingsTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    @guild = Guild.create!(id: 555_000_111_222_333_444, name: "Raid Server")
    ActsAsTenant.with_tenant(@guild) do
      @category = TeamCategory.create!(name: "PvE Teams")
      @team_type = TeamType.create!(name: "Heroic Team")
      @team = Team.create!(name: "Alpha", team_role_id: 1, officer_role_id: 2, review_channel_id: 3,
                           team_category: @category, team_type: @team_type)
    end
  end

  def refresh_jobs = enqueued_jobs.count { |job| job["job_class"] == "RosterRefreshJob" }

  test "managers can add, rename, and delete categories; roster refreshes on rename and delete" do
    sign_in_as users(:member), manageable: [ @guild ]

    assert_no_difference -> { refresh_jobs } do
      post guild_team_categories_path(@guild), params: { team_category: { name: "PvP Teams", position: "" } }
    end
    assert_redirected_to guild_path(@guild)
    ActsAsTenant.with_tenant(@guild) do
      assert_operator TeamCategory.named("PvP Teams").position, :>, @category.position
    end

    assert_difference -> { refresh_jobs } do
      patch guild_team_category_path(@guild, @category), params: { team_category: { name: "Raids ⚔️", position: 1 } }
    end
    assert_equal "Raids ⚔️", @category.reload.name

    assert_difference -> { refresh_jobs } do
      delete guild_team_category_path(@guild, @category)
    end
    assert_nil @team.reload.team_category_id # teams survive, uncategorized
  end

  test "managers can add, rename, and delete team types; roster refreshes on rename and delete" do
    sign_in_as users(:member), manageable: [ @guild ]

    post guild_team_types_path(@guild), params: { team_type: { name: "Mythic Team", position: "" } }
    assert_redirected_to guild_path(@guild)

    assert_difference -> { refresh_jobs } do
      patch guild_team_type_path(@guild, @team_type), params: { team_type: { name: "Heroic+", position: 1 } }
    end
    assert_equal "Heroic+", @team_type.reload.name

    assert_difference -> { refresh_jobs } do
      delete guild_team_type_path(@guild, @team_type)
    end
    assert_nil @team.reload.team_type_id # teams survive, just without the type line
  end

  test "members can't touch the lists or see the settings section" do
    sign_in_as users(:member), member: [ @guild ]

    get guild_path(@guild)
    assert_response :success
    assert_select "h2", text: /Roster settings/, count: 0

    post guild_team_categories_path(@guild), params: { team_category: { name: "Sneaky" } }
    assert_redirected_to guild_path(@guild)
    patch guild_team_type_path(@guild, @team_type), params: { team_type: { name: "Sneaky" } }
    delete guild_team_category_path(@guild, @category)

    ActsAsTenant.with_tenant(@guild) do
      assert_nil TeamCategory.named("Sneaky")
      assert_equal "Heroic Team", @team_type.reload.name
      assert @category.reload.persisted?
    end
  end

  test "managers see the settings section with both lists" do
    sign_in_as users(:member), manageable: [ @guild ]

    get guild_path(@guild)
    assert_response :success
    assert_select "h2", text: /Roster settings/
    assert_select "input[value=?]", "PvE Teams"
    assert_select "input[value=?]", "Heroic Team"
  end

  test "managers can rename a team (and set its emote); the roster refreshes" do
    sign_in_as users(:member), manageable: [ @guild ]

    assert_difference -> { refresh_jobs } do
      patch guild_team_path(@guild, @team),
            params: { team: { name: "Alpha Prime", emote: "⚔️", team_category_id: @category.id, team_type_id: @team_type.id } }
    end
    assert_redirected_to guild_team_path(@guild, @team)
    @team.reload
    assert_equal "Alpha Prime", @team.name
    assert_equal "⚔️", @team.emote
    assert_equal @category.id, @team.team_category_id
  end

  test "an emote shortcode is resolved against the server's emoji list" do
    sign_in_as users(:member), manageable: [ @guild ]

    stub_singleton_method(Discord::EmoteResolver, :call, "<:swordguy:9001>") do
      patch guild_team_path(@guild, @team), params: { team: { name: "Alpha", emote: ":swordguy:" } }
    end

    assert_redirected_to guild_team_path(@guild, @team)
    assert_equal "<:swordguy:9001>", @team.reload.emote
  end

  test "an unknown emote shortcode is rejected without saving" do
    sign_in_as users(:member), manageable: [ @guild ]

    raise_unknown = ->(**) { raise Discord::EmoteResolver::UnknownEmote, "nope" }
    stub_singleton_method(Discord::EmoteResolver, :call, raise_unknown) do
      patch guild_team_path(@guild, @team), params: { team: { name: "Renamed", emote: ":nope:" } }
    end

    assert_redirected_to guild_team_path(@guild, @team)
    assert_match(/no emote named :nope:/, flash[:alert])
    assert_equal "Alpha", @team.reload.name # nothing was saved
  end

  test "category and type ids from another guild are cleared, not assigned" do
    other_guild = Guild.create!(id: 666_000_111_222_333_444, name: "Other")
    other_category, other_type = ActsAsTenant.with_tenant(other_guild) do
      [ TeamCategory.create!(name: "Theirs"), TeamType.create!(name: "Their Type") ]
    end
    sign_in_as users(:member), manageable: [ @guild ]

    patch guild_team_path(@guild, @team),
          params: { team: { name: "Alpha", team_category_id: other_category.id, team_type_id: other_type.id } }

    @team.reload
    assert_nil @team.team_category_id
    assert_nil @team.team_type_id
  end
end
