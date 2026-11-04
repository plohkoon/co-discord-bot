require "test_helper"

class TeamProposalPostJobTest < ActiveJob::TestCase
  class FakeApi
    attr_reader :created

    def initialize(error: nil)
      @error = error
      @created = []
    end

    def create_message(channel_id, payload)
      raise @error if @error

      @created << [ channel_id, payload ]
      { "id" => "4242" }
    end
  end

  def guild = @guild ||= Guild.create!(id: 555_000_111_222_333_444, name: "Raid Server", team_proposals_channel_id: 900)

  setup do
    ActsAsTenant.with_tenant(guild) do
      @category = TeamCategory.create!(name: "Retail PvE Teams", proposals_enabled: true)
      @proposal = TeamProposal.create!(
        team_category: @category, discord_user_id: 42, discord_username: "thrall",
        answers: [ { "label" => "Your team", "answer" => "Tue/Thu heroic" },
                   { "label" => "Who's already on board?", "answer" => "" } ]
      )
    end
  end

  def perform(api) = TeamProposalPostJob.perform_now(guild_id: guild.id, proposal_id: @proposal.id, api: api)

  test "posts the answers to the guild's proposals channel without pinging, and records the message" do
    api = FakeApi.new
    perform(api)

    channel_id, payload = api.created.sole
    assert_equal 900, channel_id
    embed = payload["embeds"].sole
    assert_equal "New team proposal — Retail PvE Teams", embed["title"]
    assert_includes embed["description"], "<@42>"
    assert_equal [ "Tue/Thu heroic", "—" ], embed["fields"].map { |f| f["value"] } # blank answers get a dash
    assert_equal [], payload.dig("allowed_mentions", "parse")

    @proposal.reload
    assert_equal 900, @proposal.channel_id
    assert_equal 4242, @proposal.message_id
  end

  test "re-delivery of a posted proposal is a no-op" do
    @proposal.update!(message_id: 1)
    api = FakeApi.new
    perform(api)

    assert_empty api.created
  end

  test "a cleared proposals channel leaves the proposal saved but unposted" do
    guild.update!(team_proposals_channel_id: nil)
    api = FakeApi.new
    perform(api)

    assert_empty api.created
    assert_not @proposal.reload.posted?
  end

  test "a category toggled off or deleted since the submit still gets its pitch posted" do
    @category.destroy
    api = FakeApi.new
    perform(api)

    assert_equal "New team proposal", api.created.sole.last["embeds"].sole["title"]
  end

  test "a deleted or unpostable channel is logged, not retried" do
    perform(FakeApi.new(error: Discord::BotApi::Forbidden.new("Missing Access")))

    assert_not @proposal.reload.posted?
  end
end
