require "test_helper"

# Resolving the character an applicant typed.
#
# The governing rule: an application must never be lost, delayed, or degraded
# because someone misspelt their own character.
class ApplicationCharacterJobTest < ActiveJob::TestCase
  NOW = Time.utc(2026, 7, 27)
  APPLICANT = 555_000_111_222_333_444

  class FakeClient
    def initialize(profile, error: nil)
      @profile = profile
      @error = error
    end

    def character_profile(_realm, _name)
      raise @error if @error

      @profile
    end
  end

  def profile(id: 42, name: "Thrall", realm: "Sargeras", slug: "sargeras")
    { "id" => id, "name" => name, "level" => 90,
      "realm" => { "id" => 57, "name" => realm, "slug" => slug },
      "character_class" => { "name" => "Shaman" }, "faction" => { "type" => "HORDE" } }
  end

  def guild = @guild ||= Guild.create!(id: 777_000_111_222_333_444, name: "Raid Server")

  def team(**overrides)
    @team ||= ActsAsTenant.with_tenant(guild) do
      Team.create!({ name: "Alpha", team_role_id: 1, officer_role_id: 2,
                     review_channel_id: 3 }.merge(overrides))
    end
  end

  def application(input: "Thrall-Sargeras")
    @application ||= ActsAsTenant.with_tenant(guild) do
      membership = TeamMembership.create!(team: team, discord_user_id: APPLICANT,
                                          discord_username: "applicant")
      membership.team_applications.create!(team: team, discord_user_id: APPLICANT,
                                           discord_username: "applicant", character_input: input)
    end
  end

  def run_job(app = application, client: FakeClient.new(profile))
    ApplicationCharacterJob.perform_now(application_id: app.id, guild_id: guild.id, client: client)
  end

  # --- The happy path ---

  # Gathering runs inline, not enqueued: the review message repaints
  # immediately afterwards and would otherwise show an empty summary.
  test "resolves the character, claims it, and gathers its data inline" do
    app = application
    run_job(app)

    assert_no_enqueued_jobs only: WowCharacterRefreshJob
    app.reload
    character = app.wow_character
    assert_equal "Thrall-Sargeras", character.full_name
    assert_equal "Thrall-Sargeras", app.character_input, "kept verbatim even on success"
    assert_not app.character_unresolved?
    assert character.claimed?
    assert_not character.verified?, "applying proves nothing"
  end

  # An applicant almost certainly has never visited the web app.
  test "creates a shadow person for an applicant who has never signed in" do
    run_job

    user = User.find_by(discord_id: APPLICANT)
    assert user.shadow?
    assert_equal "applicant", user.username
    assert_equal [ "Thrall" ], user.wow_characters.pluck(:name)
  end

  test "the applied-on character becomes their main and the team's active character" do
    app = application
    run_job(app)

    user = User.find_by(discord_id: APPLICANT)
    assert_equal "Thrall", user.reload.main_wow_character.name
    assert_equal "Thrall", app.reload.team_membership.wow_character.name
  end

  # --- Typos ---

  test "an unrecognised character DMs the applicant and leaves the application standing" do
    app = application(input: "Thral-Sargeras")
    sent = []
    stub_singleton_method(Notifications::DirectMessage, :call, ->(**args) { sent << args }) do
      run_job(app, client: FakeClient.new(nil, error: BattleNet::Client::NotFound))
    end

    app.reload
    assert_nil app.wow_character_id
    assert app.character_unresolved?
    assert_equal "Thral-Sargeras", app.character_input, "what they typed is the only evidence of intent"
    assert_equal :pending, app.status.to_sym, "the application is untouched"
    assert_equal 1, sent.size
    assert_equal APPLICANT, sent.first[:user_id]
    assert_match(/couldn't find/i, sent.first[:content])
    assert_match(/Nothing is lost/i, sent.first[:content])
  end

  test "input in the wrong shape is reported without a Blizzard round trip" do
    app = application(input: "justaname")
    sent = []
    stub_singleton_method(Notifications::DirectMessage, :call, ->(**args) { sent << args }) do
      run_job(app, client: FakeClient.new(nil, error: RuntimeError))
    end

    assert app.reload.character_unresolved?
    assert_match(/Name-Realm/i, sent.first[:content])
  end

  # --- Conflicts and edge cases ---

  test "a character verified by someone else is not taken, and the applicant is told" do
    other = users(:admin).battle_net_accounts.create!(battle_net_id: 9, region: "us", linked_at: NOW)
    other.wow_characters.create!(blizzard_id: 42, name: "Thrall", realm: "Sargeras",
                                 realm_slug: "sargeras", verified_at: NOW)
    app = application
    sent = []
    stub_singleton_method(Notifications::DirectMessage, :call, ->(**args) { sent << args }) do
      run_job(app)
    end

    assert app.reload.character_unresolved?
    assert_equal users(:admin), WowCharacter.find_by(blizzard_id: 42).user
    assert_match(/another account/i, sent.first[:content])
  end

  test "an application with no character is a no-op" do
    app = application(input: nil)
    run_job(app)

    assert_nil app.reload.wow_character_id
  end

  test "an already-resolved application is not resolved twice" do
    app = application
    run_job(app)
    first = app.reload.wow_character_id

    run_job(app)
    assert_equal first, app.reload.wow_character_id
  end

  # The character is claimed even when the four data services are unreachable —
  # the hourly sweep fills in what's missing.
  test "a failure while gathering does not lose the resolution" do
    app = application
    stub_singleton_method(WowCharacterRefreshJob, :perform_now, ->(*, **) { raise BattleNet::Client::Error }) do
      run_job(app)
    end

    assert_equal "Thrall", app.reload.wow_character.name
  end

  test "a deleted application or guild is ignored rather than raising" do
    assert_nothing_raised do
      ApplicationCharacterJob.perform_now(application_id: 999_999, guild_id: guild.id)
      ApplicationCharacterJob.perform_now(application_id: 1, guild_id: 999_999)
    end
  end

  # Minitest 6 has no stubbing; ActiveSupport::TestCase's helper lives on the
  # integration case, so it's redefined here.
  def stub_singleton_method(mod, name, value)
    original = mod.method(name)
    mod.define_singleton_method(name) { |*args, **kwargs| value.call(*args, **kwargs) }
    yield
  ensure
    mod.define_singleton_method(name, original)
  end
end
