module Memberships
  # Reconcile a membership to "archived" — the user no longer has the team role
  # (removed, or left the server). Idempotent; keeps notes + history.
  #
  # A still-pending application is system-rejected on the way out (same Decide
  # path as the 7-day auto-reject, decided_by nil): left pending it would block
  # a re-apply via the one-pending-per-user unique index and keep firing
  # officer reminders for someone who's gone. Resolution runs even when the
  # membership was already archived, healing rows archived before this existed.
  class Archive
    def self.call(membership)
      was_archived = membership.archived?
      membership.update!(status: :archived, left_at: Time.current) unless was_archived
      resolve_pending_applications(membership)

      # Mundane audit trail — only for a genuine transition (idempotent re-calls
      # that heal an already-archived row don't re-log). After the commit, so
      # the enqueue is outside the write path.
      log_removal(membership) unless was_archived
      membership
    end

    # Role-sync entry point: reconcile "user lacks the team role". A *pending*
    # membership is left alone — an applicant awaiting review never had the
    # role, so lacking it is the expected state, not a departure (archiving
    # here would system-reject a live application on any unrelated role
    # change). Explicit removals and server departures call `call` directly.
    def self.for(team:, discord_user_id:)
      membership = TeamMembership.find_by(team_id: team.id, discord_user_id: discord_user_id)
      return if membership.nil? || membership.pending?

      call(membership)
    end

    def self.resolve_pending_applications(membership)
      membership.team_applications.pending.find_each do |application|
        # log_event: false — this reject is a side effect of the departure, not
        # a review decision; the "Member removed" line below is the one log.
        result = Applications::Decide.call(application: application, decision: :reject, decided_by_discord_id: nil, log_event: false)
        # Repaint the review message (drop Accept/Reject) — best-effort, no-op
        # until the review message exists. Skipped if an officer's concurrent
        # click won the claim; their flow repaints.
        Applications::RefreshReviewMessage.call(application) if result.status == :ok
      end
    end
    private_class_method :resolve_pending_applications

    def self.log_removal(membership)
      GuildLog.record(
        guild: ActsAsTenant.current_tenant,
        level: :low,
        title: "Member removed",
        description: "#{membership.mention} left or was removed from **#{membership.team.name}**.",
        color: 0x99AAB5
      )
    end
    private_class_method :log_removal
  end
end
