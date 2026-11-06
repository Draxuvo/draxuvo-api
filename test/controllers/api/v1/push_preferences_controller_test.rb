require "test_helper"

class Api::V1::PushPreferencesControllerTest < ActionDispatch::IntegrationTest
  setup { @company = companies(:resto_co) }

  test "staff sees only the kinds about their own work, all on by default" do
    get "/api/v1/push_preference", headers: auth_headers(users(:resto_waiter), @company)

    assert_response :ok
    assert_equal({ "available" => %w[check_ready work_order_assigned], "check_ready" => true, "work_order_assigned" => true },
                 response.parsed_body)
  end

  test "an owner sees every kind its modules allow" do
    get "/api/v1/push_preference", headers: auth_headers(users(:resto_owner), @company)

    body = response.parsed_body
    assert_equal %w[check_ready low_stock operational_alert work_order_assigned], body["available"].sort
    assert body.values_at(*body["available"]).all?(true)
  end

  test "update only changes available kinds and is per company" do
    headers = auth_headers(users(:resto_waiter), @company)
    patch "/api/v1/push_preference", params: { check_ready: false, low_stock: false }, headers: headers, as: :json

    assert_response :ok
    assert_equal false, response.parsed_body["check_ready"]
    preference = NotificationPreference.find_by(user: users(:resto_waiter), company: @company)
    assert_equal false, preference.push_check_ready
    assert_equal true, preference.push_low_stock, "el staff no puede tocar un tipo que no le corresponde"
  end

  test "a non boolean value gives 422" do
    patch "/api/v1/push_preference", params: { check_ready: "maybe" }, headers: auth_headers(users(:resto_waiter), @company), as: :json

    assert_response :unprocessable_entity
    assert_equal "invalid_value", response.parsed_body.dig("error", "details", "code")
  end

  test "the email preference endpoint keeps its shape (FR-009)" do
    get "/api/v1/notification_preference", headers: auth_headers(users(:resto_owner), @company)

    assert_equal({ "stock_email" => true }, response.parsed_body)
  end

  # --- Spec 058: «Por cobrar» ---

  test "charge_pending is offered to bosses only with owner-only charging on, and can be turned off" do
    get "/api/v1/push_preference", headers: auth_headers(users(:resto_owner), @company)
    assert_not_includes response.parsed_body["available"], "charge_pending"

    @company.update!(boss_only_charge: true)
    get "/api/v1/push_preference", headers: auth_headers(users(:resto_owner), @company)
    assert_includes response.parsed_body["available"], "charge_pending"
    assert_equal true, response.parsed_body["charge_pending"]

    get "/api/v1/push_preference", headers: auth_headers(users(:resto_waiter), @company)
    assert_not_includes response.parsed_body["available"], "charge_pending"

    patch "/api/v1/push_preference", params: { charge_pending: false }, headers: auth_headers(users(:resto_owner), @company), as: :json
    assert_response :ok
    assert_equal false, NotificationPreference.find_by(user: users(:resto_owner), company: @company).push_charge_pending
  end
end
