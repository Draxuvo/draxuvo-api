require "test_helper"

# El rol se evalúa en la empresa activa (X-Company-Id), no de forma global. FR-023, FR-024.
class Api::V1::RoleScopeControllerTest < ActionDispatch::IntegrationTest
  setup do
    # Owner en pro_co (fixture) y staff en enterprise_co.
    @user = users(:pro_co_owner)
    create_member(companies(:enterprise_co), role: :staff, user: @user)
  end

  test "owner in A and staff in B gets 200 on reports of A and 403 on reports of B" do
    get "/api/v1/reports/summary", headers: auth_headers(@user, companies(:pro_co))
    assert_response :ok

    get "/api/v1/reports/summary", headers: auth_headers(@user, companies(:enterprise_co))
    assert_response :forbidden
  end

  test "the subscription and module settings follow the role in the active company" do
    get "/api/v1/subscription", headers: auth_headers(@user, companies(:pro_co))
    assert_response :ok

    get "/api/v1/subscription", headers: auth_headers(@user, companies(:enterprise_co))
    assert_response :forbidden

    patch "/api/v1/company/modules", params: { disabled_modules: [] },
                                     headers: auth_headers(@user, companies(:enterprise_co)), as: :json
    assert_response :forbidden
  end

  test "a staff of A who is owner of B is still staff in A" do
    staff = users(:pro_staff)
    create_member(companies(:enterprise_co), role: :owner, user: staff)

    get "/api/v1/reports/summary", headers: auth_headers(staff, companies(:pro_co))
    assert_response :forbidden

    get "/api/v1/reports/summary", headers: auth_headers(staff, companies(:enterprise_co))
    assert_response :ok
  end

  test "login lists every company with the role there and keeps user.role from the first company" do
    post "/api/v1/auth/login", params: { email: @user.email, password: "password123" }, as: :json

    assert_response :ok
    user = JSON.parse(response.body)["user"]
    companies = user["companies"].index_by { |c| c["id"] }
    assert_equal "owner", companies[companies(:pro_co).id]["role"]
    assert_equal "staff", companies[companies(:enterprise_co).id]["role"]
    %w[name slug parent_company_id].each { |key| assert companies[companies(:pro_co).id].key?(key), "missing #{key}" }
    assert_equal "owner", user["role"]
  end

  test "the super admin keeps role super_admin" do
    post "/api/v1/auth/login", params: { email: users(:super_admin).email, password: "password123" }, as: :json

    assert_response :ok
    assert_equal "super_admin", JSON.parse(response.body).dig("user", "role")
  end
end
