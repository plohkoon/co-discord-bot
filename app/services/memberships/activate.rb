module Memberships
  # Reconcile a membership to "active" — the user has the team role. Idempotent.
  # Used for manual role grants (via the gateway listener and Backfill).
  #
  # If the person had a pending application, the grant IS the acceptance: it's
  # decided through the same Decide path as the buttons (decided_by nil =
  # system) so it stops firing officer reminders and can't block a later
  # re-apply. Only when there's no application history at all does a synthetic
  # accepted one get created as the record. Resolution runs even when the
  # membership was already active, healing rows activated before this existed.
  class Activate
    def self.call(team:, discord_user_id:, username: nil)
      membership = TeamMembership.find_or_create_by!(team_id: team.id, discord_user_id: discord_user_id) do |m|
        m.discord_username = username.to_s
      end
      resolve_pending_applications(membership)
      return membership if membership.active?

      membership.transaction do
        if membership.team_applications.accepted.none?
          membership.team_applications.create!(
            team: team,
            discord_user_id: discord_user_id,
            discord_username: username.presence || membership.discord_username,
            source: :manual,
            status: :accepted,
            decided_at: Time.current
          )
        end
        membership.update!(
          status: :active,
          joined_at: membership.joined_at || Time.current,
          left_at: nil,
          discord_username: username.presence || membership.discord_username
        )
      end

      membership
    end

    def self.resolve_pending_applications(membership)
      membership.team_applications.pending.find_each do |application|
        result = Applications::Decide.call(application: application, decision: :accept, decided_by_discord_id: nil)
        # Repaint the review message (drop Accept/Reject) — best-effort. Skipped
        # if an officer's concurrent click won the claim; their flow repaints.
        Applications::RefreshReviewMessage.call(application) if result.status == :ok
      end
    end
    private_class_method :resolve_pending_applications
  end
end
