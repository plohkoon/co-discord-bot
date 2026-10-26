require "test_helper"

# /guild roster categories: — one roster per channel, optionally limited to a
# comma-separated list of categories.
class GuildRosterTest < ActiveSupport::TestCase
  class FakeApi
    attr_reader :created, :deleted

    def initialize
      @created = []
      @deleted = []
      @next_id = 900
    end

    def guild_roles(_guild_id) = []

    def create_message(channel_id, payload)
      @created << [ channel_id, payload ]
      { "id" => (@next_id += 1).to_s }
    end

    def delete_message(channel_id, message_id) = @deleted << [ channel_id, message_id ]
  end

  class FakeAdmin
    def id = 42
    def permission?(kind) = kind == :manage_server
  end

  class FakeEvent
    attr_reader :options, :responses, :choices

    def initialize(options)
      @options = options
      @responses = []
    end

    def user = FakeAdmin.new
    def server = nil
    def channel = nil
    def respond(content: nil, choices: nil, **)
      choices ? @choices = choices : @responses << content
    end
  end

  CHANNEL = 700

  def guild = @guild ||= Guild.sync_from_discord(id: 1, name: "Test")

  def setup
    @api = FakeApi.new
    ActsAsTenant.with_tenant(guild) do
      @pve = TeamCategory.create!(name: "PvE Teams")
      @pvp = TeamCategory.create!(name: "PvP Teams")
      @forever = TeamCategory.create!(name: "Forever Teams")
      { "Raid" => @pve, "Arena" => @pvp, "Eternal" => @forever, "Loose" => nil }.each_with_index do |(name, category), i|
        Team.create!(name: name, team_role_id: 100 + i, officer_role_id: 200, review_channel_id: 300,
                     team_category: category)
      end
    end
  end

  def run_roster(options)
    event = FakeEvent.new({ "channel" => CHANNEL.to_s }.merge(options))
    command = Commands::Guild::Roster.new(event: event, guild: guild)
    api = @api
    command.define_singleton_method(:api) { api }
    ActsAsTenant.with_tenant(guild) { command.process }
    event
  end

  def posted_team_names
    @api.created.flat_map { |_, payload| payload["components"] }
            .filter_map { |c| c.dig("components", 0, "components", 0, "content") }
            .map { |content| content[/<@&(\d+)>/, 1].to_i }
            .map { |role_id| ActsAsTenant.with_tenant(guild) { Team.find_by(team_role_id: role_id).name } }
  end

  def roster_post = ActsAsTenant.with_tenant(guild) { RosterPost.find_by(channel_id: CHANNEL) }

  test "without categories every team is posted, uncategorized included" do
    run_roster({})

    assert_equal %w[Raid Arena Eternal Loose], posted_team_names
    assert_not roster_post.filtered?
    assert_equal [ 901 ], roster_post.message_ids
  end

  test "a category list limits the roster and is remembered on the post" do
    event = run_roster("categories" => "pve teams, PvP Teams")

    assert_match(/PvE Teams.*PvP Teams/, event.responses.first)
    assert_equal %w[Raid Arena], posted_team_names
    assert_equal [ @pve.id, @pvp.id ], roster_post.category_ids
  end

  test "an unknown category rejects the whole post" do
    event = run_roster("categories" => "PvE Teams, Classic")

    assert_match(/no category named \*\*Classic\*\*/, event.responses.first)
    assert_empty @api.created
    assert_nil roster_post
  end

  test "re-posting in a channel replaces the roster there" do
    run_roster("categories" => "PvE Teams")
    run_roster("categories" => "Forever Teams")

    assert_equal [ [ CHANNEL, 901 ] ], @api.deleted
    assert_equal [ @forever.id ], roster_post.category_ids
    assert_equal [ 902 ], roster_post.message_ids
  end

  def contents(payload) = payload["components"].filter_map { |c| c["content"] }

  test "a roster with no matching teams posts its headers to fill in later" do
    empty = ActsAsTenant.with_tenant(guild) { TeamCategory.create!(name: "Classic") }

    event = run_roster("categories" => "Classic")

    assert_match(/fills in as they're created/, event.responses.first)
    _, payload = @api.created.sole
    assert_equal [ "## Classic", "No Classic teams listed yet - they'll appear here as they're created" ],
                 contents(payload)
    assert_equal [ empty.id ], roster_post.category_ids
    assert_equal [ 901 ], roster_post.message_ids
  end

  test "an empty category keeps its header beside categories that have teams" do
    ActsAsTenant.with_tenant(guild) { TeamCategory.create!(name: "Classic") }

    run_roster("categories" => "PvE Teams, Classic")

    _, payload = @api.created.sole
    assert_equal [ "## PvE Teams", "## Classic", "No Classic teams listed yet - they'll appear here as they're created" ],
                 contents(payload)
    assert_equal %w[Raid], posted_team_names
  end

  test "autocomplete completes the last entry and skips ones already chosen" do
    event = FakeEvent.new("categories" => "PvE Teams, p")
    ActsAsTenant.with_tenant(guild) do
      Commands::Guild::Roster.new(event: event, guild: guild).autocomplete("categories")
    end

    assert_equal [ "PvE Teams, PvP Teams" ], event.choices.keys
  end
end
