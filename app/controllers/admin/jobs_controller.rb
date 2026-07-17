module Admin
  # Solid Queue monitoring: tabbed view over the queue database plus
  # retry/discard for failed executions. Queries SolidQueue's models directly —
  # they connect to the dedicated queue DB via config.solid_queue.connects_to.
  class JobsController < BaseController
    TABS = %w[all failed scheduled recurring processes].freeze

    def index
      @tab   = params[:tab].presence_in(TABS) || "all"
      @stats = build_stats
      send("load_#{@tab}")
    end

    def retry_job
      SolidQueue::FailedExecution.find(params[:id]).retry
      redirect_back fallback_location: admin_jobs_path(tab: "failed"), notice: "Job queued for retry."
    end

    def discard_job
      SolidQueue::FailedExecution.find(params[:id]).discard
      redirect_back fallback_location: admin_jobs_path(tab: "failed"), notice: "Job discarded."
    end

    def retry_all
      SolidQueue::FailedExecution.find_each(&:retry)
      redirect_back fallback_location: admin_jobs_path(tab: "failed"), notice: "All failed jobs queued for retry."
    end

    def discard_all
      SolidQueue::FailedExecution.find_each(&:discard)
      redirect_back fallback_location: admin_jobs_path(tab: "failed"), notice: "All failed jobs discarded."
    end

    private

    def build_stats
      {
        "Total"       => SolidQueue::Job.count,
        "Pending"     => SolidQueue::Job.where(finished_at: nil).count,
        "In progress" => SolidQueue::ClaimedExecution.count,
        "Failed"      => SolidQueue::FailedExecution.count,
        "Scheduled"   => SolidQueue::ScheduledExecution.count,
        "Completed"   => SolidQueue::Job.finished.count,
        "Workers"     => SolidQueue::Process.count
      }
    end

    def load_all
      jobs, @meta = paginate(SolidQueue::Job.order(created_at: :desc))
      @jobs = jobs.includes(:claimed_execution, :failed_execution, :ready_execution,
                            :scheduled_execution, :blocked_execution).to_a
    end

    def load_failed
      failed, @meta = paginate(SolidQueue::FailedExecution.order(created_at: :desc))
      @failed = failed.includes(:job).to_a
    end

    def load_scheduled
      scheduled, @meta = paginate(SolidQueue::ScheduledExecution.order(scheduled_at: :asc))
      @scheduled = scheduled.includes(:job).to_a
    end

    def load_recurring
      @tasks = SolidQueue::RecurringTask.order(:key).map do |task|
        [ task, task.recurring_executions.order(run_at: :desc).first&.run_at ]
      end
    end

    def load_processes
      @processes = SolidQueue::Process.order(last_heartbeat_at: :desc).to_a
    end

    # Which execution row exists determines the job's state.
    def job_status(job)
      return "completed"   if job.finished_at.present?
      return "failed"      if job.failed_execution.present?
      return "in_progress" if job.claimed_execution.present?
      return "scheduled"   if job.scheduled_execution.present?
      return "blocked"     if job.blocked_execution.present?
      return "ready"       if job.ready_execution.present?

      "pending"
    end
    helper_method :job_status
  end
end
