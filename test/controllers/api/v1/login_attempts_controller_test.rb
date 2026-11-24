require "test_helper"

class Api::V1::LoginAttemptsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @admin = users(:super_admin)
    @headers = auth_headers(@admin, nil)
  end

  def attempt(**attrs)
    LoginAttempt.create!({ result: "success", email: "x@ejemplo.test", channel: "panel" }.merge(attrs))
  end

  test "the super admin gets the list with the contract shape, newest first" do
    person = users(:pro_staff)
    old = attempt(user: person, email: person.email, ip: "189.203.10.4", channel: "app", user_agent: "okhttp/4.12.0",
                  created_at: 1.hour.ago)
    unknown = attempt(result: "unknown_email", email: "nadie@x.test")
    deleted = attempt(result: "wrong_password", email: "borrada@x.test")

    get "/api/v1/login_attempts", headers: @headers
    assert_response :ok
    body = response.parsed_body
    assert_equal 50, body.dig("info", "page_size")
    assert_equal [ deleted.id, unknown.id, old.id ], body["results"].map { |row| row["id"] }

    row = body["results"].last
    assert_equal({ "id" => person.id, "name" => person.full_name, "deleted" => false }, row["user"])
    assert_equal [ { "id" => companies(:pro_co).id, "name" => companies(:pro_co).name } ], row["companies"]
    assert_equal [ "189.203.10.4", "app", "App · Android", "okhttp/4.12.0" ], row.values_at("ip", "channel", "device", "user_agent")
    assert_nil body["results"][1]["user"]
    assert_equal [], body["results"][1]["companies"]
    assert_equal({ "id" => nil, "name" => nil, "deleted" => true }, body["results"][0]["user"])
  end

  test "page size defaults to 50 and stops at 100" do
    get "/api/v1/login_attempts", params: { page_size: 500 }, headers: @headers
    assert_equal 100, response.parsed_body.dig("info", "page_size")
  end

  test "filters combine" do
    match = attempt(result: "wrong_password", ip: "10.0.0.7", channel: "app", email: "a@volta.test")
    attempt(result: "wrong_password", ip: "10.0.0.8", channel: "app", email: "a@volta.test")
    attempt(result: "success", ip: "10.0.0.7", channel: "app", email: "a@volta.test")

    get "/api/v1/login_attempts", params: { result: [ "failures" ], ip: "10.0.0.7", channel: "app", q: "volta" }, headers: @headers
    assert_equal [ match.id ], response.parsed_body["results"].map { |row| row["id"] }
  end

  test "an invalid ip or date range is a 422" do
    get "/api/v1/login_attempts", params: { ip: "999.1.1.1" }, headers: @headers
    assert_response :unprocessable_entity
    assert_equal "invalid_ip", response.parsed_body.dig("error", "details", "code")

    get "/api/v1/login_attempts", params: { from: "2026-11-20", to: "2026-11-10" }, headers: @headers
    assert_response :unprocessable_entity
    assert_equal "invalid_range", response.parsed_body.dig("error", "details", "code")

    get "/api/v1/login_attempts", params: { from: "ayer" }, headers: @headers
    assert_response :unprocessable_entity
  end

  test "summary for the super admin" do
    attempt(result: "success")
    3.times { attempt(result: "wrong_password", ip: "10.0.0.9", email: "victima@x.test") }

    get "/api/v1/login_attempts/summary", headers: @headers
    assert_response :ok
    body = response.parsed_body
    assert_equal({ "success" => 1, "failures" => 3 }, body["today"])
    assert_equal 60, body["window_minutes"]
    assert_equal [ { "ip" => "10.0.0.9", "failures" => 3 } ], body["top_ips"]
    assert_equal [ { "email" => "victima@x.test", "failures" => 3 } ], body["top_emails"]
  end

  test "only the super admin can read the log" do
    [ users(:pro_co_owner), users(:pro_staff) ].each do |user|
      get "/api/v1/login_attempts", headers: auth_headers(user)
      assert_response :forbidden
      get "/api/v1/login_attempts/summary", headers: auth_headers(user)
      assert_response :forbidden
    end

    get "/api/v1/login_attempts"
    assert_response :unauthorized
  end
end
