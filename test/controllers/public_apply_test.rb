require "test_helper"

# The shareable /apply pages: Discord sign-in with return-to, a live
# membership gate (join card for non-members, enforced server-side on the
# POST), and a web application form that goes through the same
# Applications::Submit service as the Discord modal.
class PublicApplyTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

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

  # A person×team with a live, undecided application — pending membership +
  # pending application (paused when asked: still status pending, just parked).
  def create_open_application(user, team: @team, paused: false)
    ActsAsTenant.with_tenant(@guild) do
      membership = TeamMembership.create!(team: team, discord_user_id: user.discord_id,
                                          discord_username: user.username, status: :pending)
      application = membership.team_applications.create!(
        team: team, discord_user_id: user.discord_id,
        discord_username: user.username, source: :applied
      )
      application.update!(paused_at: Time.current) if paused
      [ membership, application ]
    end
  end

  # Mirror one officer into the team_officers table (the roster "Team Leads"
  # source), the way Memberships::RoleSync would.
  def add_officer(team, discord_user_id:, discord_username:)
    ActsAsTenant.with_tenant(@guild) do
      team.team_officers.create!(discord_user_id: discord_user_id, discord_username: discord_username)
    end
  end

  # --- Anonymous viewing (browsing is public; applying is not) ---

  test "an anonymous visitor sees the guild page: description, teams, sign-in CTA, no forms" do
    @guild.update!(description: "A friendly raiding community.", invite_url: "https://discord.gg/abc123")
    @team.update!(description: "We push keys and clear heroic weekly.")

    get public_guild_path(@guild.slug)

    assert_response :success
    assert_match "Raid Server", response.body
    assert_match "A friendly raiding community.", response.body
    # Team cards render in full — names, bios, apply links, closed notices.
    assert_match "Alpha", response.body
    assert_match "We push keys and clear heroic weekly.", response.body
    assert_match "Bravo is full.", response.body
    assert_select "a[href=?]", public_team_path(@guild.slug, @team.slug), text: /Apply/
    # The CTA POSTs into the OAuth flow with this page as the return origin.
    assert_select "form[action='/auth/discord'] input[name=origin][value=?]", public_guild_path(@guild.slug)
    # No join banner (that's for signed-in non-members) and no application form.
    assert_no_match(/not in the Discord server yet/, response.body)
    assert_select "input[name^='application[']", count: 0
  end

  test "an anonymous visitor sees the team page with the CTA in place of the form" do
    get public_team_path(@guild.slug, @team.slug)

    assert_response :success
    assert_match "Alpha", response.body
    assert_select "form[action='/auth/discord'] input[name=origin][value=?]",
                  public_team_path(@guild.slug, @team.slug)
    assert_select "input[name=?]", "application[q:#{@question.id}]", count: 0
    assert_select "input[name=?]", "application[character]", count: 0
  end

  test "a closed team's page shows its notice to anonymous visitors without a sign-in CTA" do
    get public_team_path(@guild.slug, @closed_team.slug)

    assert_response :success
    assert_match "Bravo is full.", response.body
    assert_select "form[action='/auth/discord']", count: 0
  end

  test "an anonymous POST is bounced to login and creates nothing" do
    assert_no_difference -> { applications_count } do
      post public_team_applications_path(@guild.slug, @team.slug),
           params: { application: { "q:#{@question.id}" => "let me in" } }
    end

    assert_redirected_to login_path
  end

  test "the Team Leads line is hidden from anonymous visitors on both public pages" do
    officer = add_officer(@team, discord_user_id: 987_654_321_000, discord_username: "raidlead")

    get public_guild_path(@guild.slug)
    assert_response :success
    assert_no_match(/Team leads/, response.body)
    assert_no_match(/raidlead/, response.body)
    assert_no_match(officer.discord_user_id.to_s, response.body)

    get public_team_path(@guild.slug, @team.slug)
    assert_response :success
    assert_no_match(/Team leads/, response.body)
    assert_no_match(/raidlead/, response.body)
    assert_no_match(officer.discord_user_id.to_s, response.body)
  end

  test "the raw snowflake fallback is never leaked to anonymous visitors" do
    # An officer without a cached username would otherwise render its Discord ID.
    officer = add_officer(@team, discord_user_id: 112_233_445_566, discord_username: "")

    get public_guild_path(@guild.slug)
    assert_response :success
    assert_no_match(officer.discord_user_id.to_s, response.body)
  end

  test "unknown and removed guilds still 404 for anonymous visitors" do
    get public_guild_path("no-such-server")
    assert_response :not_found

    @guild.mark_removed!
    get public_guild_path(@guild.slug)
    assert_response :not_found
  end

  # --- Sign-in flow + return-to ---

  test "the login page threads the return path into the OAuth form" do
    get login_path(return_to: public_guild_path(@guild.slug))

    assert_response :success
    assert_select "form[action='/auth/discord'] input[name=origin][value=?]", public_guild_path(@guild.slug)
  end

  test "the login page drops an unsafe return_to instead of forwarding it" do
    [ "https://evil.example/phish", "//evil.example", "/\\evil.example" ].each do |bad|
      get login_path(return_to: bad)

      assert_response :success
      assert_select "input[name=origin]", count: 0
    end
  end

  test "signing in lands the visitor back on the page they wanted" do
    target = public_guild_path(@guild.slug)
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

  # --- Membership branch (a banner, never a gate) ---

  test "a signed-in non-member sees the join banner with the invite link AND the teams" do
    @guild.update!(invite_url: "https://discord.gg/abc123")
    sign_in_as users(:member)

    with_membership(false) do
      get public_guild_path(@guild.slug)
    end

    assert_response :success
    assert_match "not in the Discord server yet", response.body
    assert_select "a[href=?]", "https://discord.gg/abc123"
    # Teams are visible — outsiders are the recruiting audience.
    assert_match "Alpha", response.body
    assert_select "a[href=?]", public_team_path(@guild.slug, @team.slug), text: /Apply/
  end

  test "the join banner without an invite link says to ask an admin instead of a dead button" do
    sign_in_as users(:member)

    with_membership(false) do
      get public_guild_path(@guild.slug)
    end

    assert_response :success
    assert_match "ask a server admin", response.body
  end

  test "a non-member's team page shows the banner and the application form" do
    @guild.update!(invite_url: "https://discord.gg/abc123")
    sign_in_as users(:member)

    with_membership(false) do
      get public_team_path(@guild.slug, @team.slug)
    end

    assert_response :success
    assert_match "not in the Discord server yet", response.body
    assert_select "a[href=?]", "https://discord.gg/abc123"
    assert_select "input[name=?]", "application[q:#{@question.id}]"
  end

  test "a non-member can submit — the confirmation tells them to join the server" do
    @guild.update!(invite_url: "https://discord.gg/abc123")
    sign_in_as users(:member)

    with_membership(false) do
      assert_difference -> { applications_count } do
        # The web submission produces the same officer review message as the
        # Discord modal — one shared post job.
        assert_enqueued_with(job: ReviewMessagePostJob) do
          post public_team_applications_path(@guild.slug, @team.slug),
               params: { application: { "q:#{@question.id}" => "let me in" } }
        end
      end

      assert_redirected_to public_team_path(@guild.slug, @team.slug)
      assert_match "make sure you join the Discord server", flash[:notice]
      follow_redirect!
      # The landing page repeats the join messaging (banner + invite button).
      assert_match "not in the Discord server yet", response.body
      assert_select "a[href=?]", "https://discord.gg/abc123"
      # And shows the pending state rather than the form again.
      assert_select "input[name=?]", "application[q:#{@question.id}]", count: 0
    end

    ActsAsTenant.without_tenant do
      application = TeamApplication.order(:id).last
      assert_equal users(:member).discord_id.to_s, application.discord_user_id.to_s
      assert_equal [ "let me in", "" ], application.application_answers.order(:position).map(&:answer)
      assert application.team_membership.pending?
    end
  end

  # --- The member experience ---

  test "a member sees the teams; closed teams show their notice without an apply link" do
    sign_in_as users(:member), member: [ @guild ]

    with_membership(true) do
      get public_guild_path(@guild.slug)
    end

    assert_response :success
    assert_select "a[href=?]", public_team_path(@guild.slug, @team.slug), text: /Apply/
    assert_select "a[href=?]", public_team_path(@guild.slug, @closed_team.slug), count: 0
    assert_match "Bravo is full.", response.body
    # Signed in — no sign-in CTA.
    assert_select "form[action='/auth/discord']", count: 0
  end

  test "guild members do see the Team Leads line" do
    add_officer(@team, discord_user_id: 987_654_321_000, discord_username: "raidlead")
    sign_in_as users(:member), member: [ @guild ]

    with_membership(true) do
      get public_guild_path(@guild.slug)
    end

    assert_response :success
    assert_match "Team leads", response.body
    assert_match "raidlead", response.body
  end

  test "a signed-in NON-member does NOT see the Team Leads line" do
    # A lead's handle is useless to someone outside the server (no DM, no
    # mention) and still discloses staff identity — the gate is membership,
    # not merely being signed in.
    officer = add_officer(@team, discord_user_id: 987_654_321_000, discord_username: "raidlead")
    sign_in_as users(:member)

    with_membership(false) do
      get public_team_path(@guild.slug, @team.slug)
    end

    assert_response :success
    assert_no_match(/Team leads/, response.body)
    assert_no_match(/raidlead/, response.body)
    assert_no_match(officer.discord_user_id.to_s, response.body)
  end

  test "the team page shows the questions and the character field like the Discord modal" do
    sign_in_as users(:member), member: [ @guild ]

    with_membership(true) do
      get public_team_path(@guild.slug, @team.slug)
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
        post public_team_applications_path(@guild.slug, @team.slug),
             params: { application: { "character" => "Thrall-Sargeras",
                                      "q:#{@question.id}" => "I like raiding",
                                      "q:#{@optional.id}" => "" } }
      end

      assert_redirected_to public_team_path(@guild.slug, @team.slug)
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
      post public_team_applications_path(@guild.slug, @team.slug),
           params: { application: { "q:#{@question.id}" => "first" } }

      assert_no_difference -> { applications_count } do
        post public_team_applications_path(@guild.slug, @team.slug),
             params: { application: { "q:#{@question.id}" => "second" } }
      end
    end

    assert_redirected_to public_team_path(@guild.slug, @team.slug)
    assert_match "already have a pending application", flash[:alert]
  end

  test "an open application blocks re-applying: the page shows its state, not the form" do
    create_open_application(users(:member))
    sign_in_as users(:member), member: [ @guild ]

    with_membership(true) do
      get public_team_path(@guild.slug, @team.slug)
      assert_response :success
      # State, not a second form.
      assert_select "input[name=?]", "application[q:#{@question.id}]", count: 0

      # A hand-crafted re-submit files nothing and notifies no one.
      assert_no_difference -> { applications_count } do
        assert_no_enqueued_jobs only: [ ReviewMessagePostJob, ConfirmationDmJob ] do
          post public_team_applications_path(@guild.slug, @team.slug),
               params: { application: { "q:#{@question.id}" => "again" } }
        end
      end
    end

    assert_redirected_to public_team_path(@guild.slug, @team.slug)
    assert_match "already have a pending application", flash[:alert]
  end

  test "a PAUSED application is still open — re-applying is blocked and files nothing" do
    _membership, application = create_open_application(users(:member), paused: true)
    assert application.paused?, "expected the application to be paused (still pending)"
    sign_in_as users(:member), member: [ @guild ]

    with_membership(true) do
      get public_team_path(@guild.slug, @team.slug)
      assert_select "input[name=?]", "application[q:#{@question.id}]", count: 0

      assert_no_difference -> { applications_count } do
        assert_no_enqueued_jobs only: [ ReviewMessagePostJob, ConfirmationDmJob ] do
          post public_team_applications_path(@guild.slug, @team.slug),
               params: { application: { "q:#{@question.id}" => "again" } }
        end
      end
    end

    assert_match "already have a pending application", flash[:alert]
  end

  test "a non-member with an open application is blocked from re-submitting too" do
    create_open_application(users(:member))
    # Signed in but NOT in the Discord server — apply-before-join still can't
    # duplicate an open application.
    sign_in_as users(:member)

    with_membership(false) do
      get public_team_path(@guild.slug, @team.slug)
      assert_select "input[name=?]", "application[q:#{@question.id}]", count: 0

      assert_no_difference -> { applications_count } do
        assert_no_enqueued_jobs only: [ ReviewMessagePostJob, ConfirmationDmJob ] do
          post public_team_applications_path(@guild.slug, @team.slug),
               params: { application: { "q:#{@question.id}" => "again" } }
        end
      end
    end

    assert_match "already have a pending application", flash[:alert]
  end

  test "an ARCHIVED (rejected) application still lets the user re-apply" do
    ActsAsTenant.with_tenant(@guild) do
      membership = TeamMembership.create!(team: @team, discord_user_id: users(:member).discord_id,
                                          discord_username: users(:member).username, status: :archived)
      membership.team_applications.create!(team: @team, discord_user_id: users(:member).discord_id,
                                           discord_username: users(:member).username,
                                           source: :applied, status: :rejected)
    end
    sign_in_as users(:member), member: [ @guild ]

    with_membership(true) do
      # The form is offered again — re-applying after a rejection is the flow.
      get public_team_path(@guild.slug, @team.slug)
      assert_select "input[name=?]", "application[q:#{@question.id}]"

      assert_difference -> { applications_count } do
        post public_team_applications_path(@guild.slug, @team.slug),
             params: { application: { "q:#{@question.id}" => "give me another shot" } }
      end
    end

    assert_redirected_to public_team_path(@guild.slug, @team.slug)
    assert_match "Application sent", flash[:notice]
  end

  test "rapid-fire submissions from one user are rate limited" do
    sign_in_as users(:member), member: [ @guild ]
    # The controller resolves its counter store through Rails.cache at request
    # time; test's :null_store no-ops the limiter, so swap in a real one for
    # this case (fresh, so the counter starts at zero).
    fresh_store = ActiveSupport::Cache::MemoryStore.new

    with_membership(true) do
      stub_singleton_method(Rails, :cache, fresh_store) do
        # First lands, the next four are duplicate-blocked — all under the cap,
        # none rate-limited yet.
        5.times do |i|
          post public_team_applications_path(@guild.slug, @team.slug),
               params: { application: { "q:#{@question.id}" => "try #{i}" } }
          assert_no_match(/applying too fast/, flash[:alert].to_s)
        end

        # The sixth within the minute is refused before the action even runs.
        post public_team_applications_path(@guild.slug, @team.slug),
             params: { application: { "q:#{@question.id}" => "spam" } }
        assert_redirected_to public_team_path(@guild.slug, @team.slug)
        assert_match "applying too fast", flash[:alert]
      end
    end
  end

  test "an active member of the team is told so instead of re-applying" do
    ActsAsTenant.with_tenant(@guild) do
      TeamMembership.create!(team: @team, discord_user_id: users(:member).discord_id,
                             discord_username: users(:member).username, status: :active)
    end
    sign_in_as users(:member), member: [ @guild ]

    with_membership(true) do
      get public_team_path(@guild.slug, @team.slug)
      assert_match "already a member", response.body
      assert_select "input[name=?]", "application[q:#{@question.id}]", count: 0

      assert_no_difference -> { applications_count } do
        post public_team_applications_path(@guild.slug, @team.slug),
             params: { application: { "q:#{@question.id}" => "again" } }
      end
    end

    assert_match "already a member", flash[:alert]
  end

  test "a team that isn't recruiting rejects submissions with its closed notice" do
    sign_in_as users(:member), member: [ @guild ]

    with_membership(true) do
      assert_no_difference -> { applications_count } do
        post public_team_applications_path(@guild.slug, @closed_team.slug),
             params: { application: {} }
      end
    end

    assert_redirected_to public_team_path(@guild.slug, @closed_team.slug)
    assert_equal "Bravo is full.", flash[:alert]
  end

  test "an oversized answer is clamped server-side, not stored unbounded" do
    ActsAsTenant.with_tenant(@guild) { @question.update!(max_length: 200) }
    sign_in_as users(:member), member: [ @guild ]

    with_membership(true) do
      post public_team_applications_path(@guild.slug, @team.slug),
           params: { application: { "q:#{@question.id}" => "x" * 5_000 } }
    end

    ActsAsTenant.without_tenant do
      answer = TeamApplication.order(:id).last.application_answers.find_by(question_key: "why")
      assert_equal 200, answer.answer.length
    end
  end

  test "a crafted array-shaped application param is a validation miss, not a 500" do
    sign_in_as users(:member), member: [ @guild ]

    with_membership(true) do
      assert_no_difference -> { applications_count } do
        post public_team_applications_path(@guild.slug, @team.slug),
             params: { application: [ "x" ] }
      end
    end

    assert_response :unprocessable_entity
  end

  test "missing required answers re-render the form instead of filing a blank application" do
    sign_in_as users(:member), member: [ @guild ]

    with_membership(true) do
      assert_no_difference -> { applications_count } do
        post public_team_applications_path(@guild.slug, @team.slug),
             params: { application: { "q:#{@question.id}" => "  " } }
      end
    end

    assert_response :unprocessable_entity
    assert_match "Why join?", response.body
  end

  # --- Guild states ---

  test "an unknown guild slug 404s with a friendly page" do
    sign_in_as users(:member)

    get public_guild_path("no-such-server")

    assert_response :not_found
    assert_match "isn't in this server", response.body
  end

  test "raw ids 404 — the public URLs are slug-only" do
    sign_in_as users(:member), member: [ @guild ]

    get "/apply/#{GUILD_ID}"
    assert_response :not_found

    with_membership(true) do
      get "/apply/#{@guild.slug}/teams/#{@team.id}"
    end
    assert_redirected_to public_guild_path(@guild.slug)
  end

  test "the guild and team pages resolve by their slugs" do
    assert_equal "raid-server", @guild.slug
    assert_equal "alpha", @team.slug
    sign_in_as users(:member), member: [ @guild ]

    with_membership(true) do
      get "/apply/raid-server"
      assert_response :success

      get "/apply/raid-server/teams/alpha"
      assert_response :success
    end
  end

  test "a guild the bot was kicked from 404s too" do
    @guild.mark_removed!
    sign_in_as users(:member), member: [ @guild ]

    get public_guild_path(@guild.slug)

    assert_response :not_found
  end
end
