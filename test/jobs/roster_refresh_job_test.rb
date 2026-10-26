require "test_helper"

class RosterRefreshJobTest < ActiveSupport::TestCase
  # Records reflow traffic; edit can simulate a hand-deleted message.
  class FakeApi
    attr_reader :edited, :created, :deleted
    attr_accessor :edit_error, :create_error

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
      raise create_error if create_error

      @created << [ channel_id, payload ]
      { "id" => (@next_id += 1).to_s }
    end

    def delete_message(channel_id, message_id) = @deleted << [ channel_id, message_id ]
  end

  CHANNEL = 700
  OTHER_CHANNEL = 701

  def guild = @guild ||= Guild.sync_from_discord(id: 1, name: "Test")

  def create_team(name, category: nil)
    ActsAsTenant.with_tenant(guild) do
      Team.create!(name: name, team_role_id: 100, officer_role_id: 200, review_channel_id: 300,
                   team_category: category)
    end
  end

  def create_post(channel_id = CHANNEL, message_ids:, categories: nil)
    ActsAsTenant.with_tenant(guild) do
      RosterPost.create!(channel_id: channel_id, message_ids: message_ids, category_ids: categories&.map(&:id))
    end
  end

  def create_category(name) = ActsAsTenant.with_tenant(guild) { TeamCategory.create!(name: name) }

  def setup = @api = FakeApi.new

  def run_job = RosterRefreshJob.perform_now(guild_id: guild.id, api: @api)

  def team_count(payload)
    payload["components"].count { |c| c["type"] == CoBot::RosterMessage::CONTAINER }
  end

  test "a new team joins the existing message" do
    create_team("Alpha")
    post = create_post(message_ids: [ 500 ])
    create_team("Bravo")

    run_job

    assert_equal 1, @api.edited.size
    _, message_id, payload = @api.edited.first
    assert_equal 500, message_id
    assert_equal 2, team_count(payload)
    assert_empty @api.created
    assert_equal [ 500 ], post.reload.message_ids
  end

  test "shrinking the directory deletes leftover messages" do
    create_team("Alpha")
    post = create_post(message_ids: [ 500, 501 ])

    run_job

    assert_equal [ 500 ], @api.edited.map { |_, id, _| id }
    assert_equal [ [ CHANNEL, 501 ] ], @api.deleted
    assert_equal [ 500 ], post.reload.message_ids
  end

  test "a hand-deleted message is replaced by a fresh post" do
    create_team("Alpha")
    post = create_post(message_ids: [ 500 ])
    @api.edit_error = Discord::BotApi::NotFound.new("gone")

    run_job

    assert_equal 1, @api.created.size
    assert_equal [ 901 ], post.reload.message_ids
  end

  test "a vanished channel forgets that roster" do
    create_team("Alpha")
    create_post(message_ids: [ 500 ])
    @api.edit_error = Discord::BotApi::NotFound.new("gone")
    @api.create_error = Discord::BotApi::NotFound.new("no channel")

    run_job

    assert_not ActsAsTenant.with_tenant(guild) { RosterPost.exists? }
  end

  test "each channel shows only its categories, and a recategorized team moves" do
    retail = create_category("Retail")
    forever = create_category("Forever")
    create_team("Raid", category: retail)
    eternal = create_team("Eternal", category: forever)
    create_post(CHANNEL, message_ids: [ 500 ], categories: [ retail ])
    create_post(OTHER_CHANNEL, message_ids: [ 600 ], categories: [ forever ])

    run_job
    assert_equal({ CHANNEL => 1, OTHER_CHANNEL => 1 },
                 @api.edited.to_h { |channel, _, payload| [ channel, team_count(payload) ] })

    ActsAsTenant.with_tenant(guild) { eternal.update!(team_category: retail) }
    @api.edited.clear
    run_job

    assert_equal({ CHANNEL => 2, OTHER_CHANNEL => 0 },
                 @api.edited.to_h { |channel, _, payload| [ channel, team_count(payload) ] })
    assert_empty @api.deleted # the emptied channel keeps its placeholder
  end

  test "the first team created edits the placeholder in place" do
    post = create_post(message_ids: [ 500 ])
    create_team("Alpha")

    run_job

    assert_equal [ [ CHANNEL, 500 ] ], @api.edited.map { |channel, id, _| [ channel, id ] }
    assert_equal 1, team_count(@api.edited.first.last)
    assert_empty @api.created
    assert_equal [ 500 ], post.reload.message_ids
  end

  test "a roster whose teams all go away keeps a placeholder instead of vanishing" do
    alpha = create_team("Alpha")
    post = create_post(message_ids: [ 500, 501 ])
    ActsAsTenant.with_tenant(guild) { alpha.update!(active: false) }

    run_job

    _, message_id, payload = @api.edited.sole
    assert_equal 500, message_id
    assert_equal CoBot::RosterMessage::PLACEHOLDER, payload.dig("components", 0, "content")
    assert_equal [ [ CHANNEL, 501 ] ], @api.deleted
    assert_equal [ 500 ], post.reload.message_ids
  end

  test "no-op when the roster was never posted" do
    create_team("Alpha")

    run_job

    assert_empty @api.edited
    assert_empty @api.created
  end
end
