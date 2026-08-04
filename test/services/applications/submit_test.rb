require "test_helper"

module Applications
  class SubmitTest < ActiveSupport::TestCase
    include ActiveJob::TestHelper

    FakeUser = Struct.new(:id, :username)

    # Stands in for the modal-submit event Submit reads answers from.
    #
    # `character` is kept separate from the question answers rather than
    # answering every key alike: it drives a job, so a fake that returns a
    # value for it unconditionally would enqueue work no real blank submission
    # would.
    class FakeEvent
      attr_reader :user

      def initialize(user_id, character: nil)
        @user = FakeUser.new(user_id, "alice")
        @character = character
      end

      def value(key) = key.to_s == "character" ? @character : "an answer"
    end

    def guild = @guild ||= Guild.sync_from_discord(id: 1, name: "Test")

    def team
      @team ||= ActsAsTenant.with_tenant(guild) do
        Team.create!(name: "Alpha", team_role_id: 5, officer_role_id: 6, review_channel_id: 7)
      end
    end

    def submit(character: nil)
      ActsAsTenant.with_tenant(guild) do
        Submit.call(team: team, event: FakeEvent.new(11, character: character))
      end
    end

    test "submitting schedules no per-application timers — the daily sweep owns that" do
      assert_enqueued_jobs 1 do # the confirmation DM, and nothing else
        submit
      end
      assert_enqueued_jobs 0, only: ApplicationReminderJob
      assert_enqueued_jobs 0, only: ApplicationAutoRejectJob
    end

    # The character is stored verbatim and resolved out of band, so a typo can
    # never cost someone their application.
    test "a named character is stored as typed and queued for resolution" do
      application = nil
      assert_enqueued_with(job: ApplicationCharacterJob) do
        application = submit(character: " Thrall-Sargeras ")
      end

      assert_equal "Thrall-Sargeras", application.character_input
      assert_nil application.wow_character_id, "resolution happens out of band"
      # Not "unresolved" — that would render as a typo to an officer. Until the
      # job has looked, the honest state is "still looking".
      assert application.character_pending?
      assert_not application.character_unresolved?
    end

    test "no character named means no resolution work" do
      application = submit

      assert_nil application.character_input
      assert_not application.character_asked?
      assert_enqueued_jobs 0, only: ApplicationCharacterJob
    end

    test "submitting enqueues the applicant's confirmation DM after commit" do
      assert_enqueued_with(
        job: ConfirmationDmJob,
        args: [ { guild_id: guild.id, team_id: team.id, discord_user_id: 11, kind: "apply" } ]
      ) do
        submit
      end
    end

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

    test "re-applying after the role was pulled (archive) opens a fresh pending application" do
      first = submit
      ActsAsTenant.with_tenant(guild) do
        Memberships::Archive.call(first.team_membership)
      end
      assert first.reload.rejected? # archive resolved it — nothing left to block the re-apply

      second = submit
      assert second.pending?
      assert_not_equal first.id, second.id
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
