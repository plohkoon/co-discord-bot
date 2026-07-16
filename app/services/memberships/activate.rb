module Memberships
  # Reconcile a membership to "active" — the user has the team role. Idempotent.
  # Used for manual role grants (via the gateway listener); leaves a synthetic
  # accepted application as the record if there isn't an accepted one already.
  class Activate
    def self.call(team:, discord_user_id:, username: nil)
      membership = TeamMembership.find_or_create_by!(team_id: team.id, discord_user_id: discord_user_id) do |m|
        m.discord_username = username.to_s
      end
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
  end
end
