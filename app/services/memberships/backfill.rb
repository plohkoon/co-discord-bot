module Memberships
  # One-time sweep for a new team: everyone already holding the team role
  # becomes an active member, exactly as if the role had been granted while the
  # bot was watching (same Activate path as the member_update listener, so they
  # get the synthetic accepted application with source: manual).
  #
  # Role#members chunks the server's full member list over the gateway, which
  # can take seconds on large servers — call this only AFTER the interaction
  # has been acked. Caller must have the tenant set.
  module Backfill
    module_function

    def call(team:, server:)
      role = server&.role(team.team_role_id)
      return 0 unless role

      holders = role.members.reject(&:bot_account?)
      holders.each { |member| Activate.call(team: team, discord_user_id: member.id, username: member.username) }
      holders.size
    end
  end
end
