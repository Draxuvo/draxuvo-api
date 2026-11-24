require "test_helper"

class LoginAttempts::PurgeJobTest < ActiveJob::TestCase
  def attempt(age)
    LoginAttempt.create!(result: "success", email: "x@ejemplo.test", channel: "panel", created_at: age.ago)
  end

  test "deletes attempts older than 90 days and keeps the rest" do
    old = 3.times.map { attempt(91.days) }
    kept = attempt(89.days)

    LoginAttempts::PurgeJob.perform_now

    assert_empty LoginAttempt.where(id: old.map(&:id))
    assert LoginAttempt.exists?(kept.id)
  end

  test "deletes in batches" do
    5.times { attempt(100.days) }
    LoginAttempts::PurgeJob.perform_now(batch_size: 2)
    assert_equal 0, LoginAttempt.count
  end

  test "runs every day in production" do
    task = YAML.load_file(Rails.root.join("config/recurring.yml")).fetch("production").fetch("login_attempts_purge")
    assert_equal "LoginAttempts::PurgeJob", task["class"]
    assert_equal "at 4am every day", task["schedule"]
  end
end
