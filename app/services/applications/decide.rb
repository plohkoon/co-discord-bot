module Applications
  # Accept or reject an application. Shared by the bot (Accept/Reject buttons)
  # and — later — the web dashboard.
  #
  # Correctness properties:
  #   * Idempotent under double-clicks: the status transition is claimed inside a
  #     row lock, so only the first click wins (others get :already_decided).
  #   * No network I/O inside the transaction: role assignment (a Discord REST
  #     call) runs AFTER the claim commits, via the injected role_granter.
  #   * Compensating revert: if role assignment fails, the claim is rolled back
  #     to pending so an officer can retry.
  class Decide
    class RoleError < StandardError; end

    Result = Struct.new(:status, :error, keyword_init: true)

    def self.call(...) = new(...).call

    def initialize(application:, decision:, decided_by_discord_id:, role_granter: nil)
      @application = application
      @decision = decision.to_sym          # :accept or :reject
      @decided_by = decided_by_discord_id
      @role_granter = role_granter
    end

    def call
      return Result.new(status: :already_decided) unless claim!

      if @decision == :accept && @role_granter
        begin
          @role_granter.call(@application)
        rescue RoleError => e
          revert!
          return Result.new(status: :error, error: e.message)
        end
      end

      Result.new(status: :ok)
    end

    private

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
  end
end
