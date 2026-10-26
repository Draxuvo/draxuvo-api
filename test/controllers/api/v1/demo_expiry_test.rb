require "test_helper"

# Spec 039, FR-011 y FR-018: una demo vencida o terminada deja de servir, y lo de una no afecta a otra.
class Api::V1::DemoExpiryTest < ActionDispatch::IntegrationTest
  setup { Api::V1::DemoSessionsController::RATE_LIMIT_STORE.clear }

  def open_demo(plan: "enterprise", scenario: "enterprise_restaurant")
    Demo::Provision.call(plan: plan, scenario: scenario, locale: "es")
  end

  test "an expired demo answers 403 demo_expired even though its token is still valid" do
    demo = open_demo
    demo.session.update_columns(expires_at: 1.minute.ago)

    get "/api/v1/employees", headers: auth_headers(demo.user, demo.company)

    assert_response :forbidden
    assert_equal "demo_expired", response.parsed_body.dig("error", "details", "code")
  end

  test "the same goes with the branch company of the enterprise demo" do
    demo = open_demo
    demo.session.update_columns(expires_at: 1.minute.ago)

    get "/api/v1/employees", headers: auth_headers(demo.user, demo.branch)

    assert_response :forbidden
    assert_equal "demo_expired", response.parsed_body.dig("error", "details", "code")
  end

  test "an ended demo stops serving too" do
    demo = open_demo
    demo.session.update!(ended_at: Time.current, ended_reason: "left")

    get "/api/v1/employees", headers: auth_headers(demo.user, demo.company)

    assert_response :forbidden
  end

  test "a demo that is still active keeps working, branch included" do
    demo = open_demo

    get "/api/v1/employees", headers: auth_headers(demo.user, demo.company)
    assert_response :ok
    get "/api/v1/employees", headers: auth_headers(demo.user, demo.branch)
    assert_response :ok
  end

  test "an expired demo does not affect a real company" do
    demo = open_demo
    demo.session.update_columns(expires_at: 1.minute.ago)

    get "/api/v1/employees", headers: auth_headers(users(:pro_co_owner), companies(:pro_co))

    assert_response :ok
  end

  test "an expired demo can still be finished from the screen that says it ended" do
    demo = open_demo
    demo.session.update_columns(expires_at: 1.minute.ago)

    delete "/api/v1/demo_sessions/current", headers: auth_headers(demo.user, demo.company), as: :json

    assert_response :no_content
  end

  test "after the purge the token no longer opens anything" do
    demo = open_demo
    headers = auth_headers(demo.user, demo.company)
    Demo::Purge.call(demo.company)

    get "/api/v1/employees", headers: headers

    assert_response :unauthorized
  end

  test "two visitors of the same plan never see what the other does" do
    first = open_demo(plan: "basic", scenario: "basic_retail")
    second = open_demo(plan: "basic", scenario: "basic_retail")
    first_headers = auth_headers(first.user, first.company)

    get "/api/v1/products", params: { page_size: 100 }, headers: first_headers
    total = response.parsed_body["info"]["total"]
    first.company.products.destroy_all
    first.company.employees.destroy_all

    get "/api/v1/products", params: { page_size: 100 }, headers: auth_headers(second.user, second.company)
    assert_equal total, response.parsed_body["info"]["total"]
    assert_equal 0, first.company.reload.products.count
    assert_operator second.company.employees.count, :>=, 4
  end

  test "a third visitor still gets the complete data after the first one wrecked theirs" do
    wrecked = open_demo(plan: "basic", scenario: "basic_retail")
    wrecked.company.products.destroy_all
    fresh = open_demo(plan: "basic", scenario: "basic_retail")

    assert_operator fresh.company.products.count, :>=, 12
    assert_operator fresh.company.employees.active.count, :>=, 4
  end
end
