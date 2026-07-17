require "test_helper"

class RosterRefreshJobTest < ActiveSupport::TestCase
  # Records reflow traffic; edit can simulate a hand-deleted message.
  class FakeApi
    attr_reader :edited, :created, :deleted
    attr_accessor :edit_error

    def initialize
      @edited = []
      @created = []
      @deleted = []
      @next_id = 900
    end

    def guild_roles(_guild_id) = []

    def edit_message(channel_id, message_id, payload)
      raise edit_error if edit_error

      @edited << [ channel_id, message_id, payload ]
    end

    def create_message(channel_id, payload)
      @created << [ channel_id, payload ]
      { "id" => (@next_id += 1).to_s }
    end

    def delete_message(channel_id, message_id) = @deleted << [ channel_id, message_id ]
  end

  CHANNEL = 700

  def guild = @guild ||= Guild.sync_from_discord(id: 1, name: "Test")

  def create_team(name, message_id: nil)
    ActsAsTenant.with_tenant(guild) do
      Team.create!(name: name, team_role_id: 100, officer_role_id: 200, review_channel_id: 300,
                   roster_channel_id: message_id && CHANNEL, roster_message_id: message_id)
    end
  end

  def setup = @api = FakeApi.new

  def run_job = RosterRefreshJob.perform_now(guild_id: guild.id, api: @api)

  test "a new team without roster ids joins the existing message" do
    posted = create_team("Alpha", message_id: 500)
    fresh = create_team("Bravo")

    run_job

    assert_equal 1, @api.edited.size
    _, message_id, payload = @api.edited.first
    assert_equal 500, message_id
    contents = payload["components"].flat_map { |c| c.dig("components", 0, "components", 0, "content") }
    assert_equal 2, contents.size
    assert_empty @api.created
    assert_equal [ 500, 500 ], [ posted, fresh ].map { |t| t.reload.roster_message_id }
  end

  test "shrinking the directory deletes leftover messages" do
    create_team("Alpha", message_id: 500)
    bravo = create_team("Bravo", message_id: 501)
    ActsAsTenant.with_tenant(guild) { bravo.update!(active: false) }

    run_job

    assert_equal [ 500 ], @api.edited.map { |_, id, _| id }
    assert_equal [ [ CHANNEL, 501 ] ], @api.deleted
  end

  test "a hand-deleted message is replaced by a fresh post" do
    team = create_team("Alpha", message_id: 500)
    @api.edit_error = Discord::BotApi::NotFound.new("gone")

    run_job

    assert_equal 1, @api.created.size
    assert_equal 901, team.reload.roster_message_id
  end

  test "no-op when the roster was never posted" do
    create_team("Alpha")

    run_job

    assert_empty @api.edited
    assert_empty @api.created
  end
end
