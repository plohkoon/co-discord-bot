module Applications
  # Accept or reject an application, transitioning the membership. Shared by the
  # bot (Accept/Reject buttons) and the web dashboard.
  #
  # Correctness properties:
  #   * Idempotent under double-clicks: the status transition is claimed inside a
  #     row lock, so only the first click wins (others get :already_decided).
  #   * No network I/O inside the transaction: role assignment (a Discord REST
  #     call) runs AFTER the claim commits, via the injected role_granter.
  #   * Compensating revert: if role assignment fails, the claim is rolled back
  #     to pending so an officer can retry.
  class Decide
    # role_deferred: the accept landed but the role grant was skipped because
    # the applicant isn't in the guild yet (applied from the public web page
    # before joining) — MemberJoinReconcileJob grants it when they arrive.
    Result = Struct.new(:status, :error, :role_deferred, keyword_init: true)

    def self.call(...) = new(...).call

    def initialize(application:, decision:, decided_by_discord_id:, role_granter: nil, log_event: true)
      @application = application
      @decision = decision.to_sym          # :accept or :reject
      @decided_by = decided_by_discord_id
      @role_granter = role_granter
      # Reconciliation callers (Activate/Archive resolving a stranded pending
      # application as a side effect of a role change) pass false — the primary
      # event is logged at their own seam, not here.
      @log_event = log_event
    end

    def call
      return Result.new(status: :already_decided) unless claim!

      role_deferred = false
      if @decision == :accept
        if @role_granter
          begin
            @role_granter.call(@application)
          rescue Memberships::MemberNotInGuild
            # Expected for someone who applied from the public web page before
            # joining the server: the acceptance still lands, the grant is
            # skipped, and MemberJoinReconcileJob assigns the role when they
            # join. Any other RoleError (permissions, hierarchy, vanished
            # role) still reverts and surfaces below.
            role_deferred = true
          rescue Memberships::RoleError => e
            revert!
            return Result.new(status: :error, error: e.message)
          end
        end
        activate_membership
      else
        archive_membership
      end

      log_decision
      Result.new(status: :ok, role_deferred: role_deferred)
    end

    private

    # The single decision seam for bot buttons, the web dashboard, and the
    # 7-day auto-reject. Fired after the transitions commit (no network in it —
    # it only enqueues). A human decision (decided_by present) is a mundane
    # audit line; the system auto-reject (reject with no decider) is a
    # high-priority "went unanswered" alert. A system accept (a manual role
    # grant resolving a pending app) isn't a review decision — nothing logs.
    def log_decision
      return unless @log_event

      if @decided_by
        accepted = @decision == :accept
        GuildLog.record(
          guild: ActsAsTenant.current_tenant,
          level: :low,
          title: accepted ? "Application accepted" : "Application rejected",
          description: "#{@application.applicant_mention} — **#{@application.team.name}**",
          actor_id: @decided_by,
          color: accepted ? 0x57F287 : 0xED4245
        )
      elsif @decision == :reject
        GuildLog.record(
          guild: ActsAsTenant.current_tenant,
          level: :high,
          title: "Application auto-rejected",
          description: "#{@application.applicant_mention} to **#{@application.team.name}** " \
                       "was auto-rejected after 7 days without a decision.",
          color: 0xED4245
        )
      end
    end

    def target_status = @decision == :accept ? :accepted : :rejected

    def claim!
      @application.with_lock do
        return false unless @application.pending?

        @application.update!(status: target_status,
                             decided_by_discord_id: @decided_by,
                             decided_at: Time.current)
      end
      true
    end

    def revert!
      @application.update!(status: :pending, decided_by_discord_id: nil, decided_at: nil)
    end

    def activate_membership
      membership = @application.team_membership
      membership&.update!(status: :active, joined_at: membership.joined_at || Time.current, left_at: nil)
    end

    def archive_membership
      membership = @application.team_membership
      membership&.update!(status: :archived, left_at: Time.current) if membership&.pending?
    end
  end
end
