require "test_helper"

class LoginAttemptTest < ActiveSupport::TestCase
  def attempt(**attrs)
    LoginAttempt.create!({ result: "success", email: "x@ejemplo.test", channel: "panel" }.merge(attrs))
  end

  test "validates result, channel and email" do
    record = LoginAttempt.new(result: "otro", email: "", channel: "fax")
    assert_not record.valid?
    assert record.errors.of_kind?(:result, :inclusion)
    assert record.errors.of_kind?(:channel, :inclusion)
    assert record.errors.of_kind?(:email, :blank)

    assert_not LoginAttempt.new(result: "success", channel: "app", email: "#{'a' * 250}@x.test").valid?
    LoginAttempt::RESULTS.each { |result| assert LoginAttempt.new(result: result, channel: "unknown", email: "a@b.c").valid? }
  end

  test "is insert only" do
    record = attempt
    assert record.readonly?
    assert_raises(ActiveRecord::ReadOnlyRecord) { record.update!(result: "invalid") }
  end

  test "failures excludes success" do
    attempt(result: "success")
    LoginAttempt::FAILURES.each { |result| attempt(result: result) }
    assert_equal LoginAttempt::FAILURES.sort, LoginAttempt.failures.pluck(:result).sort
  end

  test "filtered by result, including the failures shortcut" do
    ok = attempt(result: "success")
    bad = attempt(result: "wrong_password")
    blocked = attempt(result: "rate_limited")

    assert_equal [ bad.id ], LoginAttempt.filtered(result: [ "wrong_password" ]).pluck(:id)
    assert_equal [ bad.id, blocked.id ].sort, LoginAttempt.filtered(result: [ "failures" ]).pluck(:id).sort
    assert_equal [ ok.id, bad.id, blocked.id ].sort, LoginAttempt.filtered(result: [ "nada" ]).pluck(:id).sort
  end

  test "filtered by text searches the email and the person's name, escaping wildcards" do
    owner = users(:pro_co_owner)
    by_name = attempt(email: owner.email, user: owner)
    by_email = attempt(email: "cliente@volta.test")
    literal = attempt(email: "a_b@x.test")
    attempt(email: "axb@x.test")

    assert_equal [ by_name.id ], LoginAttempt.filtered(q: "ProCo").pluck(:id)
    assert_equal [ by_email.id ], LoginAttempt.filtered(q: "VOLTA").pluck(:id)
    assert_equal [ literal.id ], LoginAttempt.filtered(q: "a_b").pluck(:id)
    assert_empty LoginAttempt.filtered(q: "%").pluck(:id)
  end

  test "filtered by company keeps only people with a membership there" do
    inside = attempt(user: users(:pro_staff), email: users(:pro_staff).email)
    attempt(user: users(:basic_co_owner), email: users(:basic_co_owner).email)
    attempt(email: "nadie@x.test", result: "unknown_email")

    assert_equal [ inside.id ], LoginAttempt.filtered(company_id: companies(:pro_co).id).pluck(:id)
  end

  test "filtered by ip, channel and since" do
    from_ip = attempt(ip: "189.203.10.4", channel: "app")
    attempt(ip: "10.0.0.1", channel: "panel", created_at: 2.hours.ago)

    assert_equal [ from_ip.id ], LoginAttempt.filtered(ip: "189.203.10.4").pluck(:id)
    assert_equal [ from_ip.id ], LoginAttempt.filtered(channel: "app").pluck(:id)
    assert_equal [ from_ip.id ], LoginAttempt.filtered(since: "60").pluck(:id)
  end

  test "filtered by dates uses Mexico City days and includes the whole last day" do
    zone = Time.find_zone!("America/Mexico_City")
    early = attempt(created_at: zone.parse("2026-11-20 00:05"))
    late = attempt(created_at: zone.parse("2026-11-21 23:59"))
    attempt(created_at: zone.parse("2026-11-19 23:59"))
    attempt(created_at: zone.parse("2026-11-22 00:01"))

    ids = LoginAttempt.filtered(from: "2026-11-20", to: "2026-11-21").pluck(:id)
    assert_equal [ early.id, late.id ].sort, ids.sort
  end

  test "recent orders newest first" do
    old = attempt(created_at: 1.hour.ago)
    fresh = attempt
    assert_equal [ fresh.id, old.id ], LoginAttempt.recent.pluck(:id)
  end
end
