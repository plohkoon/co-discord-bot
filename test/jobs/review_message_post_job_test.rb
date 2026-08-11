require "test_helper"

class ReviewMessagePostJobTest < ActiveSupport::TestCase
  setup do
    @guild = Guild.sync_from_discord(id: 1, name: "Test")
    ActsAsTenant.with_tenant(@guild) do
      @team = Team.create!(name: "Alpha", team_role_id: 5, officer_role_id: 6, review_channel_id: 7)
      @membership = TeamMembership.create!(team: @team, discord_user_id: 11, discord_username: "alice", status: :pending)
      @application = @membership.team_applications.create!(team: @team, discord_user_id: 11,
                                                          discord_username: "alice", source: :applied)
    end
  end

  def perform(application_id: @application.id)
    ReviewMessagePostJob.perform_now(guild_id: @guild.id, application_id: application_id)
  end

  def stub_post(&block)
    posted = []
    stub_singleton_method(CoBot::ReviewMessage, :post, ->(**kwargs) { posted << kwargs }) { block.call }
    posted
  end

  test "posts the review message for a fresh pending application" do
    posted = stub_post { perform }

    assert_equal 1, posted.size
    assert_equal @team.id, posted.sole[:team].id
    assert_equal @application.id, posted.sole[:application].id
  end

  test "an application that already has its message posts nothing — re-delivery is safe" do
    ActsAsTenant.with_tenant(@guild) { @application.update!(review_channel_id: 7, review_message_id: 99) }

    assert_empty stub_post { perform }
  end

  test "an application decided before the job ran posts nothing" do
    ActsAsTenant.with_tenant(@guild) { @application.update!(status: :rejected, decided_at: Time.current) }

    assert_empty stub_post { perform }
  end

  test "a vanished application or guild is a quiet no-op" do
    assert_empty(stub_post { perform(application_id: 999_999) })
    assert_nothing_raised { ReviewMessagePostJob.perform_now(guild_id: 999, application_id: @application.id) }
  end

  test "a missing channel is logged, not raised — retrying can't fix configuration" do
    boom = ->(**) { raise Discord::BotApi::NotFound, "404" }
    stub_singleton_method(CoBot::ReviewMessage, :post, boom) do
      assert_nothing_raised { perform }
    end
  end
end
