module Admin
  class DashboardController < BaseController
    def index
      ActsAsTenant.without_tenant do
        @stats = {
          "Servers"       => Guild.installed.count,
          "Active teams"  => Team.where(active: true).count,
          "Pending apps"  => TeamApplication.where(status: :pending).count,
          "Users"         => User.count
        }
        @model_counts = models.map { |key, klass| [ key, klass, klass.count ] }
      end

      @job_stats = {
        "Failed"      => SolidQueue::FailedExecution.count,
        "In progress" => SolidQueue::ClaimedExecution.count,
        "Scheduled"   => SolidQueue::ScheduledExecution.count,
        "Workers"     => SolidQueue::Process.count
      }
    end
  end
end
