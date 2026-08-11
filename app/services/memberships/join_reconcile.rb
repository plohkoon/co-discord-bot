module Memberships
  # Someone just joined the server: grant the team role for every ACTIVE
  # membership they already hold — the second half of "apply from the web
  # before joining" (an officer accepted them while they weren't in the guild,
  # so the grant was deferred to this moment). Pending memberships are left
  # alone (an applicant awaiting review has no role by design) and archived
  # ones stay archived.
  #
  # Idempotent: roles the member already holds are skipped, and Discord's role
  # PUT is a no-op on re-delivery anyway. The grant triggers a member_update,
  # which flows through RoleSync -> Activate — also idempotent (the membership
  # is already active), so the two paths can't fight.
  #
  # Runs from MemberJoinReconcileJob, never on the gateway thread — everything
  # here is REST.
  class JoinReconcile
    def self.call(guild:, discord_user_id:, api: Discord::BotApi.new)
      return unless api.configured?

      memberships = ActsAsTenant.with_tenant(guild) do
        TeamMembership.active.where(discord_user_id: discord_user_id).includes(:team).to_a
      end
      return if memberships.empty?

      held = current_role_ids(api, guild.id, discord_user_id) or return # left again already

      memberships.each do |membership|
        team = membership.team
        next if team.nil? || held.include?(team.team_role_id.to_i)

        begin
          RestRoleManager.grant(team: team, discord_user_id: discord_user_id, api: api)
          Rails.logger.info("[memberships] join reconcile granted #{team.name} to #{discord_user_id} in guild #{guild.id}")
        rescue MemberNotInGuild
          return # left again mid-run — nothing further to grant
        rescue RoleError => e
          # One team's misconfiguration (hierarchy, vanished role) must not
          # block the member's other teams.
          Rails.logger.warn("[memberships] join reconcile couldn't grant #{team.name} to #{discord_user_id} in guild #{guild.id}: #{e.message}")
        end
      end
    end

    # The member's current role ids, or nil when they aren't in the guild
    # (joined and left again before the job ran).
    def self.current_role_ids(api, guild_id, discord_user_id)
      member = api.guild_member(guild_id, discord_user_id)
      Array(member["roles"]).map(&:to_i).to_set
    rescue Discord::BotApi::NotFound
      nil
    end
    private_class_method :current_role_ids
  end
end
