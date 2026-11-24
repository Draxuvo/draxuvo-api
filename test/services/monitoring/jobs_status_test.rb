require "test_helper"

class Monitoring::JobsStatusTest < ActiveSupport::TestCase
  SECRET_ARG = "argumento-secreto-cliente".freeze

  setup do
    [ SolidQueue::RecurringExecution, SolidQueue::FailedExecution, SolidQueue::ClaimedExecution, SolidQueue::ReadyExecution,
      SolidQueue::ScheduledExecution, SolidQueue::Job, SolidQueue::Process, SolidQueue::RecurringTask ].each(&:delete_all)
  end

  def process(heartbeat_at)
    SolidQueue::Process.create!(kind: "Worker", last_heartbeat_at: heartbeat_at, pid: 1, hostname: "h",
                                name: "worker-#{SecureRandom.hex(3)}")
  end

  def job(class_name = "Push::ReceiptsJob", scheduled_at: Time.current)
    SolidQueue::Job.create!(queue_name: "default", class_name: class_name, scheduled_at: scheduled_at,
                            arguments: { "arguments" => [ SECRET_ARG ] })
  end

  def fail_job(job, message, at: Time.current)
    job.ready_execution&.destroy!
    SolidQueue::FailedExecution.create!(job: job, error: { "exception_class" => "Net::ReadTimeout", "message" => message,
                                                           "backtrace" => [ "a.rb:1" ] }, created_at: at)
  end

  test "ok with a recent heartbeat and nothing failing" do
    process(2.minutes.ago)
    status = Monitoring::JobsStatus.call
    assert_equal "ok", status[:state]
    assert_in_delta 2.minutes.ago, status[:last_heartbeat_at], 5
  end

  test "down without a heartbeat in more than 10 minutes, or without processes" do
    assert_equal "down", Monitoring::JobsStatus.call[:state]

    process(11.minutes.ago)
    status = Monitoring::JobsStatus.call
    assert_equal "down", status[:state]
    assert_in_delta 11.minutes.ago, status[:last_heartbeat_at], 5
  end

  test "counts pending (ready plus due scheduled) and running" do
    worker = process(1.minute.ago)
    job
    job(scheduled_at: 1.minute.ago)
    job(scheduled_at: 1.hour.from_now)
    running = job
    running.ready_execution.destroy!
    SolidQueue::ClaimedExecution.create!(job: running, process: worker)

    status = Monitoring::JobsStatus.call
    assert_equal 2, status[:pending]
    assert_equal 1, status[:running]
  end

  test "lists the last 20 failures of 24 hours without their arguments" do
    process(1.minute.ago)
    fail_job(job("Old::Job"), "viejo", at: 25.hours.ago)
    22.times { |i| fail_job(job, "falla #{i} #{'x' * 400}", at: i.minutes.ago) }

    status = Monitoring::JobsStatus.call
    assert_equal "warn", status[:state]
    assert_equal 22, status[:failed_24h]
    assert_equal 20, status[:failures].size
    first = status[:failures].first
    assert_equal [ "Push::ReceiptsJob", "Net::ReadTimeout" ], [ first[:job_class], first[:error_class] ]
    assert_equal 300, first[:message].length
    assert first[:message].start_with?("falla 0")
    assert_not_includes status.to_json, SECRET_ARG
    assert_not_includes status.to_json, "a.rb:1"
  end

  test "a recurring task without a run in more than two periods is late" do
    process(1.minute.ago)
    late = SolidQueue::RecurringTask.create!(key: "monitoring_heartbeat", schedule: "every 5 minutes",
                                             class_name: "Monitoring::HeartbeatJob", static: true, created_at: 1.day.ago)
    on_time = SolidQueue::RecurringTask.create!(key: "push_receipts", schedule: "every 15 minutes",
                                                class_name: "Push::ReceiptsJob", static: true, created_at: 1.day.ago)
    SolidQueue::RecurringTask.create!(key: "brand_new", schedule: "every hour", class_name: "Push::ReceiptsJob",
                                      static: true, created_at: 1.minute.ago)
    SolidQueue::RecurringExecution.create!(job: job, task_key: late.key, run_at: 20.minutes.ago)
    SolidQueue::RecurringExecution.create!(job: job, task_key: on_time.key, run_at: 10.minutes.ago)

    status = Monitoring::JobsStatus.call
    assert_equal "warn", status[:state]
    assert_equal [ "monitoring_heartbeat" ], status[:late].map { |task| task[:key] }
    assert_equal 300, status[:late].first[:expected_every_seconds]
  end
end
