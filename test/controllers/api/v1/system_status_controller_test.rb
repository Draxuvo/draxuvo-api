require "test_helper"

class Api::V1::SystemStatusControllerTest < ActionDispatch::IntegrationTest
  test "the super admin gets every card even without third party tokens" do
    with_memory_cache do
      with_env(BETTERSTACK_UPTIME_TOKEN: nil, SENTRY_API_TOKEN: nil) do
        get "/api/v1/system_status", params: { refresh: 1 }, headers: auth_headers(users(:super_admin), nil)
      end
    end

    assert_response :ok
    body = response.parsed_body
    assert_equal %w[api checked_at database errors jobs links uptime], body.keys.sort
    assert_equal "unconfigured", body.dig("uptime", "state")
    assert_equal "unconfigured", body.dig("errors", "state")
    assert_equal "ok", body.dig("database", "state")
  end

  test "only the super admin can read it" do
    [ users(:pro_co_owner), users(:pro_staff) ].each do |user|
      get "/api/v1/system_status", headers: auth_headers(user)
      assert_response :forbidden
    end

    get "/api/v1/system_status"
    assert_response :unauthorized
  end
end
