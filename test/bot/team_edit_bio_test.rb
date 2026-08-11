require "test_helper"

# /team edit description: — the officer-level bio, assigned through the same
# ROSTER_FIELDS loop (and lenient emote resolution) as the other roster lines.
class TeamEditBioTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  OFFICER_ROLE = 200

  FakeRole = Struct.new(:id)

  # An officer: no Discord-level manage permission, just the team's officer
  # role — the gate /team edit actually checks.
  class FakeMember
    def initialize(role_ids)
      @role_ids = role_ids
    end

    def id = 42
    def permission?(_kind) = false
    def roles = @role_ids.map { |id| FakeRole.new(id) }
  end

  # A slash-command interaction: options as Discord delivers them (string keys).
  class FakeEvent
    attr_reader :user, :options, :responses

    def initialize(user:, options:)
      @user = user
      @options = options
      @responses = []
    end

    def server = nil
    def respond(content: nil, **) = @responses << content
  end

  def guild = @guild ||= Guild.create!(id: 777_000_111_222_333_555, name: "Raid Server")

  def team
    @team ||= ActsAsTenant.with_tenant(guild) do
      Team.create!(name: "Alpha", team_role_id: 100, officer_role_id: OFFICER_ROLE, review_channel_id: 300)
    end
  end

  def run_edit(options, roles: [ OFFICER_ROLE ])
    event = FakeEvent.new(user: FakeMember.new(roles), options: { "team" => team.id.to_s }.merge(options))
    ActsAsTenant.with_tenant(guild) do
      Commands::Team::Edit.new(event: event, guild: guild, params: {}).process
    end
    event
  end

  test "an officer sets the bio and the roster reflows" do
    event = run_edit({ "description" => "  Laid-back AOTC crew.  " })

    assert_match(/Updated/, event.responses.first)
    assert_equal "Laid-back AOTC crew.", team.reload.description
    assert_enqueued_with(job: RosterRefreshJob)
  end

  test "an over-long bio is rejected with the validation error" do
    event = run_edit({ "description" => "x" * 501 })

    assert_match(/too long/, event.responses.first)
    assert_nil team.reload.description
  end

  test "a non-officer can't set the bio" do
    event = run_edit({ "description" => "sneaky" }, roles: [])

    assert_match(/officers/, event.responses.first)
    assert_nil team.reload.description
  end

  test ":name: shortcodes in the bio resolve leniently" do
    fake_resolve = ->(guild_id:, input:, **) { input.to_s.gsub(":swordguy:", "<:swordguy:9001>") }
    stub_singleton_method(Discord::EmoteResolver, :resolve_text, fake_resolve) do
      run_edit({ "description" => "We bring :swordguy: energy" })
    end

    assert_equal "We bring <:swordguy:9001> energy", team.reload.description
  end
end
