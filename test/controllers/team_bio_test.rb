require "test_helper"

# The bio is part of the officer toolkit like the other roster lines — a team
# lead sets it on the web team page, and saving it reflows the posted roster.
class TeamBioTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    @guild = Guild.create!(id: 888_000_111_222_333_666, name: "Raid Server")
    ActsAsTenant.with_tenant(@guild) do
      @team = Team.create!(name: "Alpha", team_role_id: 1, officer_role_id: 2, review_channel_id: 3)
      TeamOfficer.create!(team: @team, discord_user_id: users(:member).discord_id,
                          discord_username: users(:member).username)
    end
  end

  def refresh_jobs = enqueued_jobs.count { |job| job["job_class"] == "RosterRefreshJob" }

  test "a team lead can set the bio, and it reflows the roster" do
    sign_in_as users(:member), member: [ @guild ]

    assert_difference -> { refresh_jobs }, 1 do
      patch guild_team_path(@guild, @team),
            params: { team: { description: "Laid-back AOTC crew — alts welcome." } }
    end

    assert_redirected_to guild_team_path(@guild, @team)
    assert_equal "Laid-back AOTC crew — alts welcome.", @team.reload.description
  end

  test "plain members can't set the bio" do
    ActsAsTenant.with_tenant(@guild) { TeamOfficer.delete_all }
    sign_in_as users(:member), member: [ @guild ]

    patch guild_team_path(@guild, @team), params: { team: { description: "sneaky" } }

    assert_redirected_to guild_path(@guild)
    assert_nil @team.reload.description
  end

  test "a bio over 500 characters is rejected with the error shown" do
    sign_in_as users(:member), member: [ @guild ]

    patch guild_team_path(@guild, @team), params: { team: { description: "x" * 501 } }

    assert_redirected_to guild_team_path(@guild, @team)
    assert_match(/too long/, flash[:alert])
    assert_nil @team.reload.description
  end

  test "inline :name: shortcodes resolve in the bio like the other roster lines" do
    sign_in_as users(:member), member: [ @guild ]

    fake_resolve = ->(guild_id:, input:, **) { input.to_s.gsub(":swordguy:", "<:swordguy:9001>") }
    stub_singleton_method(Discord::EmoteResolver, :resolve_text, fake_resolve) do
      patch guild_team_path(@guild, @team),
            params: { team: { description: "We bring :swordguy: energy + :unknown:" } }
    end

    assert_equal "We bring <:swordguy:9001> energy + :unknown:", @team.reload.description
  end
end
