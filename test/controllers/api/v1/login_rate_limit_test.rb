require "test_helper"

class LoginRateLimitTest < ActionDispatch::IntegrationTest
  setup do
    Api::V1::AuthenticationController::RATE_LIMIT_STORE.clear
    @user = users(:pro_staff)
  end

  test "the 11th failed attempt is blocked even with the right password, but password recovery still answers" do
    10.times do
      post "/api/v1/auth/login", params: { email: @user.email, password: "mala" }, as: :json
      assert_response :unauthorized
    end
    post "/api/v1/auth/login", params: { email: @user.email, password: "Clave-Segura-9" }, as: :json
    assert_response :too_many_requests
    assert_equal 900, response.parsed_body.dig("error", "details", "retry_after")

    post "/api/v1/passwords/reset", params: { email: @user.email }, as: :json
    assert_not_equal 429, response.status
  end

  test "another account is not blocked by someone else's attempts" do
    10.times { post "/api/v1/auth/login", params: { email: @user.email, password: "mala" }, as: :json }
    post "/api/v1/auth/login", params: { email: users(:expired_staff).email, password: "mala" }, as: :json
    assert_response :unauthorized
  end
end
