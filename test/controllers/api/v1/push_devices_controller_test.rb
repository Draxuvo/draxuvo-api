require "test_helper"

class Api::V1::PushDevicesControllerTest < ActionDispatch::IntegrationTest
  TOKEN = "ExponentPushToken[device-abcdef]".freeze

  setup do
    @company = companies(:resto_co)
    @waiter = users(:resto_waiter)
    @headers = auth_headers(@waiter, @company)
  end

  def register(headers: @headers, **params)
    post "/api/v1/push_devices", params: { token: TOKEN, platform: "android", locale: "es", app_version: "1.1.0" }.merge(params),
                                 headers: headers, as: :json
  end

  test "registers the device of the signed-in person without exposing the token" do
    register

    assert_response :ok
    body = response.parsed_body
    assert_equal "android", body["platform"]
    assert_equal "abcdef", body["token_hint"]
    assert_not_includes response.body, "device-abcdef"
    assert_equal @waiter, PushDevice.find_by(token: TOKEN).user
  end

  test "the same phone moves to whoever signs in next" do
    register
    register(headers: auth_headers(users(:resto_waiter2), @company))

    assert_equal users(:resto_waiter2), PushDevice.find_by(token: TOKEN).user
    assert_equal 1, PushDevice.where(token: TOKEN).count
  end

  test "invalid token or platform gives 422 with its code" do
    register(token: "nope")
    assert_response :unprocessable_entity
    assert_equal "invalid_token", response.parsed_body.dig("error", "details", "code")

    register(platform: "windows")
    assert_response :unprocessable_entity
    assert_equal "invalid_platform", response.parsed_body.dig("error", "details", "code")
  end

  test "X-Company-Id is required and must be one of the person's companies" do
    register(headers: auth_headers(@waiter, nil))
    assert_response :bad_request

    register(headers: auth_headers(@waiter, nil).merge("X-Company-Id" => companies(:pro_co).id.to_s))
    assert_response :forbidden
  end

  test "works while the company's subscription has no access (FR-005a)" do
    @company.subscription.update_columns(status: Subscription.statuses[:suspended])

    register
    assert_response :ok

    delete "/api/v1/push_devices/#{ERB::Util.url_encode(TOKEN)}", headers: @headers
    assert_response :no_content
    assert_not PushDevice.exists?(token: TOKEN)
  end

  test "delete is idempotent and never touches someone else's device" do
    register(headers: auth_headers(users(:resto_waiter2), @company))

    delete "/api/v1/push_devices/#{ERB::Util.url_encode(TOKEN)}", headers: @headers
    assert_response :no_content
    assert PushDevice.exists?(token: TOKEN), "no es del mesero que lo pide"

    delete "/api/v1/push_devices/#{ERB::Util.url_encode("ExponentPushToken[missing]")}", headers: @headers
    assert_response :no_content
  end
end
