require "test_helper"

class LoginAttempts::RecordTest < ActiveSupport::TestCase
  BROWSER = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36".freeze

  def fake_request(headers = {}, ip: "189.203.10.4")
    env = { "REMOTE_ADDR" => ip }
    headers.each { |key, value| env["HTTP_#{key.upcase.tr('-', '_')}"] = value }
    ActionDispatch::Request.new(Rack::MockRequest.env_for("/api/v1/auth/login", env))
  end

  def record(headers = {}, email: "Persona@Ejemplo.TEST ", result: "success", user: nil, ip: "189.203.10.4")
    LoginAttempts::Record.call(request: fake_request(headers, ip: ip), email: email, result: result, user: user)
    LoginAttempt.order(:id).last
  end

  test "the client header decides the channel when it is known" do
    assert_equal "panel", record({ "X-Draxuvo-Client" => "panel", "User-Agent" => "okhttp/4.12.0" }).channel
    assert_equal "app", record({ "X-Draxuvo-Client" => "APP", "User-Agent" => BROWSER }).channel
  end

  test "without a known header the user agent decides" do
    assert_equal "app", record({ "X-Draxuvo-Client" => "fax", "User-Agent" => "okhttp/4.12.0" }).channel
    assert_equal "app", record({ "User-Agent" => "Draxuvo/12 CFNetwork/1568.100.1 Darwin/24.0.0" }).channel
    assert_equal "panel", record({ "User-Agent" => BROWSER }).channel
    assert_equal "unknown", record({ "User-Agent" => "curl/8.7.1" }).channel
    assert_equal "unknown", record.channel
  end

  test "normalizes and trims what it stores" do
    attempt = record({ "User-Agent" => "Mozilla/5.0 #{'x' * 900}", "X-Draxuvo-Client-Version" => "v" * 80 },
                     email: "  #{'A' * 300}@X.TEST ")
    assert_equal 254, attempt.email.length
    assert_equal attempt.email, attempt.email.downcase
    assert_equal 500, attempt.user_agent.length
    assert_equal 50, attempt.client_version.length
    assert_equal "persona@ejemplo.test", record.email
  end

  test "keeps the client ip and drops one that cannot be parsed" do
    assert_equal "189.203.10.4", record.ip.to_s
    assert_nil record(ip: "no-es-ip").ip
  end

  test "demo only when every membership is a demo company" do
    user = users(:pro_staff)
    assert_not record(user: user).demo

    companies(:pro_co).update_columns(demo: true)
    assert record(user: user).demo

    assert_not record(user: users(:super_admin)).demo
    assert_not record.demo
  end

  test "a failure to save never raises, is reported once and logs without the email" do
    reported = []
    logs = StringIO.new
    original = Rails.logger
    Rails.logger = ActiveSupport::Logger.new(logs)

    LoginAttempt.stub(:create!, ->(*) { raise ActiveRecord::StatementInvalid, "boom" }) do
      Sentry.stub(:capture_exception, ->(error, **) { reported << error }) do
        assert_nothing_raised { LoginAttempts::Record.call(request: fake_request, email: "secreto@x.test", result: "success") }
      end
    end

    assert_equal 1, reported.size
    assert_includes logs.string, "[LoginAttempts::Record] no se guardó: ActiveRecord::StatementInvalid"
    assert_not_includes logs.string, "secreto@x.test"
  ensure
    Rails.logger = original
  end
end
