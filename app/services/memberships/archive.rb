module Memberships
  # Reconcile a membership to "archived" — the user no longer has the team role
  # (removed, or left the server). Idempotent; keeps notes + history.
  class Archive
    def self.call(membership)
      return membership if membership.archived?

      membership.update!(status: :archived, left_at: Time.current)
      membership
    end

    def self.for(team:, discord_user_id:)
      membership = TeamMembership.find_by(team_id: team.id, discord_user_id: discord_user_id)
      membership && call(membership)
    end
  end
end
