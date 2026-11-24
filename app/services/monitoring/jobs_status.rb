# Tarjeta «Trabajos en segundo plano» del estado del sistema (spec 073, research R8). Lee las tablas de Solid Queue de la
# base principal: si el worker da señal, cuántos trabajos esperan o corren, los fallidos recientes (sin sus argumentos,
# que pueden llevar datos de clientes) y los trabajos programados que no han corrido cuando debían.
module Monitoring
  class JobsStatus
    STALE_AFTER = 10.minutes
    FAILURES_WINDOW = 24.hours
    FAILURES_SHOWN = 20
    MESSAGE_MAX = 300
    LATE_PERIODS = 2

    def self.call = new.call

    def call
      last_heartbeat = SolidQueue::Process.maximum(:last_heartbeat_at)
      failed = SolidQueue::FailedExecution.where(created_at: FAILURES_WINDOW.ago..)
      late = late_tasks
      {
        state: state(last_heartbeat, failed.exists?, late.any?),
        last_heartbeat_at: last_heartbeat,
        pending: SolidQueue::ReadyExecution.count + SolidQueue::ScheduledExecution.where(scheduled_at: ..Time.current).count,
        running: SolidQueue::ClaimedExecution.count,
        failed_24h: failed.count,
        failures: failures(failed),
        late: late
      }
    end

    private

    def state(last_heartbeat, any_failed, any_late)
      return "down" if last_heartbeat.nil? || last_heartbeat < STALE_AFTER.ago
      return "warn" if any_failed || any_late

      "ok"
    end

    # Solo la clase del trabajo: nunca `solid_queue_jobs.arguments`.
    def failures(scope)
      rows = scope.joins(:job).order(created_at: :desc).limit(FAILURES_SHOWN)
                  .pluck("solid_queue_jobs.class_name", :error, :created_at)
      rows.map do |job_class, error, at|
        error = parse_error(error)
        { job_class: job_class, error_class: error["exception_class"],
          message: error["message"].to_s.truncate(MESSAGE_MAX, omission: "…"), at: at }
      end
    end

    def parse_error(raw)
      raw.is_a?(Hash) ? raw : JSON.parse(raw.to_s)
    rescue JSON::ParserError
      {}
    end

    def late_tasks
      last_runs = SolidQueue::RecurringExecution.group(:task_key).maximum(:run_at)
      SolidQueue::RecurringTask.order(:key).filter_map do |task|
        period = period_of(task)
        next unless period

        reference = [ last_runs[task.key], task.created_at ].compact.max
        next unless reference < (LATE_PERIODS * period).seconds.ago

        { key: task.key, last_run_at: last_runs[task.key], expected_every_seconds: period.round }
      end
    end

    def period_of(task)
      (task.next_time - task.previous_time).to_f
    rescue StandardError
      nil
    end
  end
end
