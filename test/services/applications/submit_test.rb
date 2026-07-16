require "test_helper"

module Applications
  class SubmitTest < ActiveSupport::TestCase
    FakeUser = Struct.new(:id, :username)

    # Stands in for the modal-submit event Submit reads answers from.
    class FakeEvent
      attr_reader :user

      def initialize(user_id)
        @user = FakeUser.new(user_id, "alice")
      end

      def value(_key) = "an answer"
    end

    def guild = @guild ||= Guild.sync_from_discord(id: 1, name: "Test")

    def team
      @team ||= ActsAsTenant.with_tenant(guild) do
        Team.create!(name: "Alpha", team_role_id: 5, officer_role_id: 6, review_channel_id: 7)
      end
    end

    def submit = ActsAsTenant.with_tenant(guild) { Submit.call(team: team, event: FakeEvent.new(11)) }

    test "a second application while one is pending raises DuplicatePending" do
      application = submit
      assert application.pending?

      assert_raises(Submit::DuplicatePending) { submit }
      ActsAsTenant.with_tenant(guild) do
        assert_equal 1, TeamApplication.where(discord_user_id: 11).count
      end
    end

    test "re-applying after a rejection opens a fresh pending application" do
      first = submit
      ActsAsTenant.with_tenant(guild) do
        Decide.call(application: first, decision: :reject, decided_by_discord_id: 99)
      end

      second = submit
      assert second.pending?
      assert_not_equal first.id, second.id
      ActsAsTenant.with_tenant(guild) do
        assert first.reload.team_membership.pending?
      end
    end

    test "an active member cannot apply" do
      first = submit
      ActsAsTenant.with_tenant(guild) do
        Decide.call(application: first, decision: :accept, decided_by_discord_id: 99)
      end

      assert_raises(Submit::AlreadyMember) { submit }
    end
  end
end
