require "test_helper"

module Teams
  # Deleting a team takes every row that hangs off it — and nothing belonging
  # to the guild's other teams — then hands the role removal to a job.
  class DeleteTest < ActiveSupport::TestCase
    include ActiveJob::TestHelper

    def guild = @guild ||= Guild.sync_from_discord(id: 1, name: "Test")

    def make_team(name, role_id)
      ActsAsTenant.with_tenant(guild) do
        Team.create!(name: name, team_role_id: role_id, officer_role_id: 6, review_channel_id: 7).tap(&:seed_default_questions!)
      end
    end

    # One of everything a team owns.
    def populate(team)
      ActsAsTenant.with_tenant(guild) do
        membership = TeamMembership.create!(team: team, discord_user_id: 11, discord_username: "alice", status: :active)
        MembershipNote.create!(team_membership: membership, author_discord_id: 99, body: "solid healer")
        application = TeamApplication.create!(team: team, team_membership: membership, discord_user_id: 11)
        ApplicationAnswer.create!(team_application: application, question_key: "why", question_label: "Why?", answer: "fun")
        TeamOfficer.create!(team: team, discord_user_id: 99)
        Absence.create!(team: team, team_membership: membership, discord_user_id: 11, discord_username: "alice",
                        absence_on: Date.new(2026, 11, 20), created_by_discord_id: 11)
        AbsenceDigest.create!(team: team, digest_on: Date.new(2026, 11, 20))
        WowauditCharacter.create!(team: team, wowaudit_id: 1, name: "Thrall", synced_at: Time.current)
      end
    end

    OWNED = [ TeamMembership, MembershipNote, TeamApplication, ApplicationAnswer, TeamOfficer,
              ApplicationQuestion, Absence, AbsenceDigest, WowauditCharacter ].freeze

    # Deserialized kwargs of every enqueued GuildLogJob.
    def guild_log_args
      enqueued_jobs.select { |j| j["job_class"] == "GuildLogJob" }
                   .map { |j| ActiveJob::Arguments.deserialize(j["arguments"]).first }
    end

    def counts = ActsAsTenant.without_tenant { OWNED.index_with(&:count) }

    test "deletes the team and everything it owns, leaving other teams alone" do
      doomed = make_team("Alpha", 5)
      kept = make_team("Bravo", 8)
      populate(doomed)
      populate(kept)
      before = counts

      ActsAsTenant.with_tenant(guild) { Delete.call(team: doomed) }

      ActsAsTenant.with_tenant(guild) do
        assert_not Team.exists?(doomed.id)
        assert Team.exists?(kept.id)
      end
      after = counts
      OWNED.each do |model|
        assert_equal before[model] / 2, after[model], "#{model} should keep only Bravo's rows"
      end
      ActsAsTenant.with_tenant(guild) do
        assert_equal 1, kept.team_memberships.count
        assert_equal 1, kept.team_memberships.sole.membership_notes.count
      end
    end

    test "queues the role removal by role id, plus a roster refresh" do
      team = make_team("Alpha", 5)

      ActsAsTenant.with_tenant(guild) { Delete.call(team: team) }

      assert_enqueued_with(job: TeamRoleStripJob, args: [ { guild_id: guild.id, role_id: 5, team_name: "Alpha" } ])
      assert_enqueued_with(job: RosterRefreshJob, args: [ { guild_id: guild.id } ])
    end

    test "logs the deletion to the guild's important log" do
      guild.update!(important_log_channel_id: 4242)
      team = make_team("Alpha", 5)

      ActsAsTenant.with_tenant(guild) { Delete.call(team: team, actor_id: 99) }

      log = guild_log_args.sole
      assert_equal [ "Team deleted", :high, 99 ], log.values_at(:title, :level, :actor_id)
      assert_includes log[:description], "Alpha"
    end
  end
end
