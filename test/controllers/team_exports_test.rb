require "test_helper"
require "csv"

# The team-wide applications table (a column per question) and the two CSV
# exports — applications and members. Lead-only, like the membership page.
class TeamExportsTest < ActionDispatch::IntegrationTest
  setup do
    @guild = Guild.create!(id: 888_000_111_222_333_444, name: "Raid Server")
    ActsAsTenant.with_tenant(@guild) do
      @team = Team.create!(name: "Alpha", team_role_id: 1, officer_role_id: 2, review_channel_id: 3)
      @team.application_questions.create!(key: "class", label: "Class", position: 0)
      @team.application_questions.create!(key: "times", label: "Availability", position: 1)

      @mage = WowCharacter.create!(user: users(:member), blizzard_id: 9001, name: "Frostbyte", realm: "Thrall",
                                   realm_slug: "thrall", region: "us", playable_class: "Mage", active_spec: "Frost")

      @alice = TeamMembership.create!(team: @team, discord_user_id: 41, discord_username: "alice",
                                      status: :active, wow_character: @mage)
      @bob = TeamMembership.create!(team: @team, discord_user_id: 42, discord_username: "bob", status: :pending)

      apply(@alice, status: :accepted, created_at: 2.days.ago, character: @mage,
            answers: { "class" => [ "Class", "Mage" ], "old" => [ "Old question", "kept" ] })
      apply(@bob, status: :pending, created_at: 1.day.ago, input: "Typo-Thrall",
            answers: { "class" => [ "What class?", "=HYPERLINK(\"http://evil\")" ], "times" => [ "Availability", "Weeknights" ] })
      TeamOfficer.create!(team: @team, discord_user_id: users(:member).discord_id, discord_username: users(:member).username)
    end
    sign_in_as users(:member), member: [ @guild ]
  end

  def apply(membership, status:, created_at:, answers:, character: nil, input: nil)
    application = TeamApplication.create!(team: @team, team_membership: membership, discord_user_id: membership.discord_user_id,
                                          discord_username: membership.discord_username, status: status, created_at: created_at,
                                          wow_character: character, character_input: input || character&.full_name)
    answers.each_with_index do |(key, (label, answer)), i|
      application.application_answers.create!(question_key: key, question_label: label, answer: answer, position: i)
    end
  end

  def parsed = CSV.parse(response.body.delete_prefix("﻿"), headers: true)

  test "the applications page shows every application with a column per question" do
    get guild_team_applications_path(@guild, @team)

    assert_response :success
    # Current questions first under today's labels, then the retired one.
    assert_equal [ "Applicant", "Applied", "Status", "Character", "Spec / class", "Class", "Availability", "Old question" ],
                 css_select("thead th").map { |th| th.text.strip }
    assert_select "tbody tr", 2
    assert_select "tbody td", text: "Frost Mage"
    assert_select "tbody td", text: "Typo-Thrall"
  end

  test "the status filter narrows the table" do
    get guild_team_applications_path(@guild, @team, status: "pending")

    assert_select "tbody tr", 1
    assert_select "tbody a", text: "bob"
  end

  test "applications CSV: one row per application, answers aligned to questions, formulas neutralised" do
    get guild_team_applications_path(@guild, @team, format: :csv)

    assert_response :success
    assert_equal "text/csv", response.media_type
    assert_match(/attachment; filename="#{@team.slug}-applications-\d{4}-\d\d-\d\d\.csv"/, response.headers["Content-Disposition"])
    assert response.body.start_with?("﻿")

    rows = parsed
    assert_equal %w[bob alice], rows.map { |r| r["Applicant"] }
    bob, alice = rows.entries
    # The question is titled "Class" too — the character's own columns are
    # prefixed so the two never share a header.
    assert_equal "'=HYPERLINK(\"http://evil\")", bob["Class"]
    assert_equal "Weeknights", bob["Availability"]
    assert_nil bob["Old question"]
    assert_equal "Typo-Thrall", bob["Character"]

    assert_equal "Frostbyte-Thrall", alice["Character"]
    assert_equal "Mage", alice["Character class"]
    assert_equal "Frost", alice["Character spec"]
    assert_equal "Mage", alice["Class"]
    assert_equal "kept", alice["Old question"]
  end

  test "the applications CSV respects the status filter" do
    get guild_team_applications_path(@guild, @team, format: :csv, status: "accepted")

    assert_equal %w[alice], parsed.map { |r| r["Applicant"] }
    assert_match(/accepted-applications/, response.headers["Content-Disposition"])
  end

  test "members CSV: one row per member with their character" do
    get guild_team_memberships_path(@guild, @team, format: :csv)

    assert_response :success
    rows = parsed
    assert_equal %w[alice bob], rows.map { |r| r["Member"] }
    alice, bob = rows.entries
    assert_equal "active", alice["Status"]
    assert_equal "Frostbyte-Thrall", alice["Character"]
    assert_equal "Mage", alice["Character class"]
    assert_equal "1", alice["Applications"]
    # No resolved character: falls back to what they typed.
    assert_equal "Typo-Thrall", bob["Character"]
    assert_equal "pending", bob["Last application status"]
  end

  test "someone who isn't a lead can't see or export applications" do
    ActsAsTenant.with_tenant(@guild) { TeamOfficer.delete_all }

    get guild_team_applications_path(@guild, @team)
    assert_redirected_to guild_path(@guild)

    get guild_team_applications_path(@guild, @team, format: :csv)
    assert_redirected_to guild_path(@guild)

    get guild_team_memberships_path(@guild, @team, format: :csv)
    assert_redirected_to guild_path(@guild)
  end

  test "the team page links to the applications table and both exports" do
    get guild_team_path(@guild, @team)

    assert_select "a[href=?]", guild_team_applications_path(@guild, @team)
    assert_select "a[href=?]", guild_team_memberships_path(@guild, @team, format: :csv)
    assert_select "a[href=?]", guild_team_applications_path(@guild, @team, format: :csv)
  end
end
