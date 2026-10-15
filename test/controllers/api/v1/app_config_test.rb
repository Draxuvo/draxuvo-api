require "test_helper"

# Contrato: specs/011-app-movil-hibrida/contracts/api-y-app.md ("GET /app_config").
class Api::V1::AppConfigTest < ActionDispatch::IntegrationTest
  PATH = "/api/v1/app_config".freeze

  test "defaults to 0.0.0 for both platforms without a token or company" do
    with_env("MIN_APP_VERSION_IOS" => nil, "MIN_APP_VERSION_ANDROID" => nil) { get PATH }

    assert_response :ok
    assert_equal({ "ios" => "0.0.0", "android" => "0.0.0" }, response.parsed_body["min_app_version"])
  end

  test "reads each platform from its environment variable" do
    with_env("MIN_APP_VERSION_IOS" => "1.2.0", "MIN_APP_VERSION_ANDROID" => "1.3.1") { get PATH }

    assert_equal({ "ios" => "1.2.0", "android" => "1.3.1" }, response.parsed_body["min_app_version"])
  end

  test "a blank variable falls back to the default" do
    with_env("MIN_APP_VERSION_IOS" => "", "MIN_APP_VERSION_ANDROID" => nil) { get PATH }

    assert_equal "0.0.0", response.parsed_body.dig("min_app_version", "ios")
  end

  test "answers 200 for a signed-in user with no company header" do
    user = users(:pro_staff)
    token = JwtHelper.jwt_encode(user_id: user.id, email: user.email, full_name: user.full_name)

    get PATH, headers: { "Authorization" => "Bearer #{token}" }

    assert_response :ok
  end
end
