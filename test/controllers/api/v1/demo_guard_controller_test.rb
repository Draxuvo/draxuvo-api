require "test_helper"

# Spec 039: lo que ve y puede hacer quien está en una demo, y que nunca llega a una empresa real.
class Api::V1::DemoGuardControllerTest < ActionDispatch::IntegrationTest
  setup do
    Api::V1::DemoSessionsController::RATE_LIMIT_STORE.clear
    @demo = Demo::Provision.call(plan: "pro", scenario: "pro_service", locale: "es")
    @headers = auth_headers(@demo.user, @demo.company)
  end

  test "the user serializer marks the demo company" do
    get "/api/v1/profile", headers: @headers

    assert_response :ok
    assert_equal [ true ], response.parsed_body["companies"].map { |company| company["demo"] }
  end

  test "a real user is not marked as demo" do
    owner = users(:pro_co_owner)
    get "/api/v1/profile", headers: auth_headers(owner, companies(:pro_co))

    assert_response :ok
    assert response.parsed_body["companies"].none? { |company| company["demo"] }
  end

  test "the subscription of a demo says so, and plan changes and payments are refused" do
    get "/api/v1/subscription", headers: @headers
    assert_response :ok
    assert_equal true, response.parsed_body["demo"]

    patch "/api/v1/subscription", headers: @headers, params: { plan: "enterprise" }, as: :json
    assert_response :forbidden
    assert_equal "demo_restricted", response.parsed_body.dig("error", "details", "code")
    assert_equal "plan_change", response.parsed_body.dig("error", "details", "action")

    post "/api/v1/subscription/checkout", headers: @headers, params: { plan: "pro" }, as: :json
    assert_response :forbidden
    assert_equal "payment", response.parsed_body.dig("error", "details", "action")

    post "/api/v1/subscription/portal", headers: @headers, as: :json
    assert_response :forbidden
    delete "/api/v1/subscription", headers: @headers
    assert_response :forbidden
  end

  test "a plan without WhatsApp still refuses it in a demo" do
    ticket = @demo.company.tickets.first
    post "/api/v1/tickets/#{ticket.id}/send_whatsapp", headers: @headers, params: { phone: "5512345678" }, as: :json

    assert_response :forbidden
    assert_equal "module_not_in_plan", response.parsed_body.dig("error", "details", "code")
  end

  test "sending a ticket by WhatsApp from the enterprise demo is simulated and sends nothing" do
    enterprise = Demo::Provision.call(plan: "enterprise", scenario: "enterprise_restaurant", locale: "es")
    ticket = enterprise.company.tickets.first
    Net::HTTP.stub(:start, ->(*) { flunk "se llamó a WhatsApp desde una demo" }) do
      post "/api/v1/tickets/#{ticket.id}/send_whatsapp", headers: auth_headers(enterprise.user, enterprise.company),
                                                          params: { phone: "5512345678" }, as: :json
    end

    assert_response :ok
    assert_equal true, response.parsed_body["demo"]
  end

  test "the demo user cannot reach a real company even with its header" do
    get "/api/v1/employees", headers: auth_headers(@demo.user, companies(:pro_co)).merge("Authorization" => @headers["Authorization"])

    assert_response :forbidden
  end

  test "the reserved demo owner cannot be used to read a real company's data through its slug or id" do
    get "/api/v1/companies/#{companies(:pro_co).id}", headers: @headers

    assert_includes [ 403, 404 ], response.status
  end
end
