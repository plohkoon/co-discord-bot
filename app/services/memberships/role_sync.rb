module Memberships
  # Reconcile a member's team memberships against the roles they currently hold.
  # Driven by the gateway (member_update / member_leave) — requires the Server
  # Members privileged intent. Idempotent: has the team role -> Activate, lacks
  # it -> Archive. This is what auto-records manual role grants/removals.
  class RoleSync
    def self.reconcile(server:, member:, roles:)
      return unless server && member

      guild = Guild.sync_from_discord(id: server.id, name: server.name)
      role_ids = Array(roles).map(&:id).to_set
      username = member.respond_to?(:username) ? member.username.to_s : nil

      ActsAsTenant.with_tenant(guild) do
        Team.all.find_each do |team|
          if role_ids.include?(team.team_role_id)
            Activate.call(team: team, discord_user_id: member.id, username: username)
          else
            Archive.for(team: team, discord_user_id: member.id)
          end

          if sync_officer(team, member.id, username, officer: role_ids.include?(team.officer_role_id)) &&
             team.roster_message_id
            # The leads line changed — repaint the posted roster.
            RosterRefreshJob.perform_later(guild_id: guild.id)
          end
        end
      end
    end

    # Keep the local officers mirror in step with the officer role. Returns
    # true when the mirror actually changed.
    def self.sync_officer(team, user_id, username, officer:)
      if officer
        record = TeamOfficer.find_or_initialize_by(team_id: team.id, discord_user_id: user_id)
        record.discord_username = username.to_s if username.present?
        changed = record.new_record? || record.changed?
        record.save! if changed
        changed
      else
        TeamOfficer.where(team_id: team.id, discord_user_id: user_id).delete_all.positive?
      end
    end

    # Member left the server -> archive all their (non-archived) memberships.
    def self.on_leave(server:, user_id:)
      return unless server && user_id

      guild = Guild.find_by(id: server.id)
      return unless guild

      ActsAsTenant.with_tenant(guild) do
        TeamMembership.where(discord_user_id: user_id).where.not(status: :archived).find_each do |membership|
          Archive.call(membership)
        end

        departed_team_ids = TeamOfficer.where(discord_user_id: user_id).pluck(:team_id)
        TeamOfficer.where(discord_user_id: user_id).delete_all
        if Team.where(id: departed_team_ids).where.not(roster_message_id: nil).exists?
          RosterRefreshJob.perform_later(guild_id: guild.id)
        end
      end
    end
  end
end
