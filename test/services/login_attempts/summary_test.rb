require "test_helper"

class LoginAttempts::SummaryTest < ActiveSupport::TestCase
  def attempt(**attrs)
    LoginAttempt.create!({ result: "success", email: "x@ejemplo.test", channel: "panel" }.merge(attrs))
  end

  test "today starts at midnight in Mexico City" do
    zone = Time.find_zone!("America/Mexico_City")
    travel_to zone.parse("2026-11-24 10:00") do
      attempt(created_at: zone.parse("2026-11-24 00:01"))
      attempt(result: "inactive", created_at: zone.parse("2026-11-24 09:00"))
      attempt(created_at: zone.parse("2026-11-23 23:59"))
      attempt(result: "wrong_password", created_at: zone.parse("2026-11-23 23:59"))

      assert_equal({ success: 1, failures: 1 }, LoginAttempts::Summary.call[:today])
    end
  end

  test "top ips and emails count failures of the last hour, rate limited included" do
    4.times { attempt(result: "wrong_password", ip: "10.0.0.1", email: "a@x.test") }
    attempt(result: "rate_limited", ip: "10.0.0.1", email: "a@x.test")
    2.times { attempt(result: "unknown_email", ip: "10.0.0.2", email: "b@x.test") }
    attempt(result: "success", ip: "10.0.0.3", email: "c@x.test")
    attempt(result: "wrong_password", ip: "10.0.0.4", email: "d@x.test", created_at: 61.minutes.ago)
    6.times { |i| attempt(result: "invalid", ip: "10.0.1.#{i}", email: "e#{i}@x.test") }

    summary = LoginAttempts::Summary.call
    assert_equal 60, summary[:window_minutes]
    assert_equal 5, summary[:top_ips].size
    assert_equal({ ip: "10.0.0.1", failures: 5 }, summary[:top_ips].first)
    assert_equal({ ip: "10.0.0.2", failures: 2 }, summary[:top_ips].second)
    assert_equal({ email: "a@x.test", failures: 5 }, summary[:top_emails].first)
    assert_not_includes summary[:top_emails].map { |row| row[:email] }, "c@x.test"
    assert_not_includes summary[:top_emails].map { |row| row[:email] }, "d@x.test"
  end

  test "empty when nothing failed" do
    assert_equal({ today: { success: 0, failures: 0 }, window_minutes: 60, top_ips: [], top_emails: [] }, LoginAttempts::Summary.call)
  end
end
