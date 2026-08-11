require "test_helper"

# The shareable /apply pages: Discord sign-in with return-to, a live
# membership gate (join card for non-members, enforced server-side on the
# POST), and a web application form that goes through the same
# Applications::Submit service as the Discord modal.
class PublicApplyTest < ActionDispatch::IntegrationTest
  GUILD_ID = 555_000_111_222_333_444

  setup do
    @guild = Guild.create!(id: GUILD_ID, name: "Raid Server")
    ActsAsTenant.with_tenant(@guild) do
      @team = Team.create!(name: "Alpha", team_role_id: 1, officer_role_id: 2, review_channel_id: 3)
      @question = @team.application_questions.create!(position: 0, key: "why", label: "Why join?", required: true)
      @optional = @team.application_questions.create!(position: 1, key: "extra", label: "Anything else?",
                                                      required: false, style: :paragraph)
      @closed_team = Team.create!(name: "Bravo", team_role_id: 4, officer_role_id: 5, review_channel_id: 6,
                                  recruiting: false, closed_message: "{team} is full.")
    end
  end

  # Pin the live membership answer — no test may reach Discord.
  def with_membership(result, &block)
    stub_singleton_method(Discord::GuildMembership, :call, result, &block)
  end

  # Sign in the way a shared link does: through the login form's POST (whose
  # `origin` param OmniAuth stores) and then the mocked callback — so the
  # return-to mechanism is exercised end to end, not just sessions#create.
  def sign_in_via_login_form(user, origin:, member: [])
    OmniAuth.config.test_mode = true
    OmniAuth.config.mock_auth[:discord] = OmniAuth::AuthHash.new(
      provider: "discord",
      uid: user.discord_id.to_s,
      info: { name: user.username },
      credentials: { token: "test-token" },
      extra: { raw_info: { "username" => user.username, "global_name" => user.global_name } }
    )
    result = Discord::ManageableGuilds::Result.new([], [], Array(member).map { |g| g.id.to_s })
    stub_singleton_method(Discord::ManageableGuilds, :call, result) do
      stub_singleton_method(Discord::Connections, :call, []) do
        post "/auth/discord", params: { origin: origin }
        follow_redirect! # the mocked request phase redirects straight to the callback
      end
    end
  ensure
    OmniAuth.config.mock_auth[:discord] = nil
    OmniAuth.config.test_mode = false
  end

  def applications_count = ActsAsTenant.without_tenant { TeamApplication.count }

  # --- Sign-in gate + return-to ---

  test "an anonymous visitor is sent to login with a return path" do
    get public_guild_path(GUILD_ID)

    assert_redirected_to login_path(return_to: public_guild_path(GUILD_ID))
  end

  test "the login page threads the return path into the OAuth form" do
    get login_path(return_to: public_guild_path(GUILD_ID))

    assert_response :success
    assert_select "form[action='/auth/discord'] input[name=origin][value=?]", public_guild_path(GUILD_ID)
  end

  test "the login page drops an unsafe return_to instead of forwarding it" do
    [ "https://evil.example/phish", "//evil.example", "/\\evil.example" ].each do |bad|
      get login_path(return_to: bad)

      assert_response :success
      assert_select "input[name=origin]", count: 0
    end
  end

  test "signing in lands the visitor back on the page they wanted" do
    target = public_guild_path(GUILD_ID)
    sign_in_via_login_form(users(:member), origin: target, member: [ @guild ])

    assert_redirected_to target
    with_membership(true) do
      follow_redirect!
      assert_response :success
    end
  end

  test "a full-URL origin is ignored — no open redirect" do
    sign_in_via_login_form(users(:member), origin: "https://evil.example/phish")

    assert_redirected_to root_path
  end

  test "protocol-relative origins are ignored too" do
    sign_in_via_login_form(users(:member), origin: "//evil.example")
    assert_redirected_to root_path

    delete logout_path
    sign_in_via_login_form(users(:member), origin: "/\\evil.example")
    assert_redirected_to root_path
  end

  # --- Membership branch ---

  test "a signed-in non-member sees the join card with the invite link, not the teams" do
    @guild.update!(invite_url: "https://discord.gg/abc123")
    sign_in_as users(:member)

    with_membership(false) do
      get public_guild_path(GUILD_ID)
    end

    assert_response :success
    assert_match "not a member of this server", response.body
    assert_select "a[href=?]", "https://discord.gg/abc123"
    assert_no_match "Alpha", response.body
    assert_select "a[href=?]", public_team_path(GUILD_ID, @team), count: 0
  end

  test "the join card without an invite link says to ask an admin instead of a dead button" do
    sign_in_as users(:member)

    with_membership(false) do
      get public_guild_path(GUILD_ID)
    end

    assert_response :success
    assert_match "ask a server admin", response.body
  end

  test "a non-member cannot submit an application — enforced server-side" do
    sign_in_as users(:member)

    with_membership(false) do
      assert_no_difference -> { applications_count } do
        post public_team_applications_path(GUILD_ID, @team),
             params: { application: { "q:#{@question.id}" => "let me in" } }
      end
    end

    assert_redirected_to public_guild_path(GUILD_ID)
  end

  # --- The member experience ---

  test "a member sees the teams; closed teams show their notice without an apply link" do
    sign_in_as users(:member), member: [ @guild ]

    with_membership(true) do
      get public_guild_path(GUILD_ID)
    end

    assert_response :success
    assert_select "a[href=?]", public_team_path(GUILD_ID, @team), text: /Apply/
    assert_select "a[href=?]", public_team_path(GUILD_ID, @closed_team), count: 0
    assert_match "Bravo is full.", response.body
  end

  test "the team page shows the questions and the character field like the Discord modal" do
    sign_in_as users(:member), member: [ @guild ]

    with_membership(true) do
      get public_team_path(GUILD_ID, @team)
    end

    assert_response :success
    assert_match "Your character (Name-Realm)", response.body
    assert_match "Why join?", response.body
    assert_match "Anything else?", response.body
    assert_select "input[name=?]", "application[q:#{@question.id}]"
    assert_select "textarea[name=?]", "application[q:#{@optional.id}]"
    assert_select "input[name=?]", "application[character]"
  end

  test "a member can apply from the web — same Submit path as the modal" do
    sign_in_as users(:member), member: [ @guild ]

    with_membership(true) do
      assert_difference -> { applications_count } do
        post public_team_applications_path(GUILD_ID, @team),
             params: { application: { "character" => "Thrall-Sargeras",
                                      "q:#{@question.id}" => "I like raiding",
                                      "q:#{@optional.id}" => "" } }
      end

      assert_redirected_to public_team_path(GUILD_ID, @team)
      follow_redirect!
      assert_match "Application sent", response.body
      # The form is gone: the page now shows the pending state.
      assert_select "input[name=?]", "application[q:#{@question.id}]", count: 0
    end

    ActsAsTenant.without_tenant do
      application = TeamApplication.order(:id).last
      assert_equal users(:member).discord_id.to_s, application.discord_user_id.to_s
      assert_equal "applied", application.source
      assert_equal "Thrall-Sargeras", application.character_input
      assert_equal [ "Why join?", "Anything else?" ], application.application_answers.order(:position).map(&:question_label)
      assert_equal [ "I like raiding", "" ], application.application_answers.order(:position).map(&:answer)
      assert application.team_membership.pending?
    end
  end

  test "a duplicate application gets a friendly message, not a crash" do
    sign_in_as users(:member), member: [ @guild ]

    with_membership(true) do
      post public_team_applications_path(GUILD_ID, @team),
           params: { application: { "q:#{@question.id}" => "first" } }

      assert_no_difference -> { applications_count } do
        post public_team_applications_path(GUILD_ID, @team),
             params: { application: { "q:#{@question.id}" => "second" } }
      end
    end

    assert_redirected_to public_team_path(GUILD_ID, @team)
    assert_match "already have a pending application", flash[:alert]
  end

  test "an active member of the team is told so instead of re-applying" do
    ActsAsTenant.with_tenant(@guild) do
      TeamMembership.create!(team: @team, discord_user_id: users(:member).discord_id,
                             discord_username: users(:member).username, status: :active)
    end
    sign_in_as users(:member), member: [ @guild ]

    with_membership(true) do
      get public_team_path(GUILD_ID, @team)
      assert_match "already a member", response.body
      assert_select "input[name=?]", "application[q:#{@question.id}]", count: 0

      assert_no_difference -> { applications_count } do
        post public_team_applications_path(GUILD_ID, @team),
             params: { application: { "q:#{@question.id}" => "again" } }
      end
    end

    assert_match "already a member", flash[:alert]
  end

  test "a team that isn't recruiting rejects submissions with its closed notice" do
    sign_in_as users(:member), member: [ @guild ]

    with_membership(true) do
      assert_no_difference -> { applications_count } do
        post public_team_applications_path(GUILD_ID, @closed_team),
             params: { application: {} }
      end
    end

    assert_redirected_to public_team_path(GUILD_ID, @closed_team)
    assert_equal "Bravo is full.", flash[:alert]
  end

  test "missing required answers re-render the form instead of filing a blank application" do
    sign_in_as users(:member), member: [ @guild ]

    with_membership(true) do
      assert_no_difference -> { applications_count } do
        post public_team_applications_path(GUILD_ID, @team),
             params: { application: { "q:#{@question.id}" => "  " } }
      end
    end

    assert_response :unprocessable_entity
    assert_match "Why join?", response.body
  end

  # --- Guild states ---

  test "an unknown guild 404s with a friendly page" do
    sign_in_as users(:member)

    get public_guild_path(999)

    assert_response :not_found
    assert_match "isn't in this server", response.body
  end

  test "a guild the bot was kicked from 404s too" do
    @guild.mark_removed!
    sign_in_as users(:member), member: [ @guild ]

    get public_guild_path(GUILD_ID)

    assert_response :not_found
  end
end
