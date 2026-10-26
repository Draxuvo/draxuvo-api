require "test_helper"

# Contrato: specs/039-demo-por-plan/contracts/api.md (POST /demo_sessions).
class Api::V1::DemoSessionsControllerTest < ActionDispatch::IntegrationTest
  setup { Api::V1::DemoSessionsController::RATE_LIMIT_STORE.clear }

  def open_demo(params = {})
    post "/api/v1/demo_sessions", params: { plan: "basic", locale: "es" }.merge(params), as: :json
  end

  test "opens a demo without a session and returns the signed-in user and when it ends" do
    open_demo

    assert_response :created
    body = response.parsed_body
    assert body["token"].present?
    assert_equal "basic", body["plan"]
    assert_equal "basic_retail", body["scenario"]
    assert body["expires_at"].present?
    company = Company.find(body["company_id"])
    assert company.demo?
    demo_flags = body.dig("user", "companies").map { |entry| entry["demo"] }
    assert_equal [ true ], demo_flags
  end

  test "the token works against the demo company and not against a real one" do
    open_demo
    token = response.parsed_body["token"]
    company_id = response.parsed_body["company_id"]

    get "/api/v1/employees", headers: { "Authorization" => "Bearer #{token}", "X-Company-Id" => company_id.to_s }
    assert_response :ok

    get "/api/v1/employees", headers: { "Authorization" => "Bearer #{token}", "X-Company-Id" => companies(:pro_co).id.to_s }
    assert_response :forbidden
  end

  test "Pro needs the business type and each one opens its scenario" do
    open_demo(plan: "pro")
    assert_response :bad_request

    open_demo(plan: "pro", scenario: "pro_restaurant")
    assert_response :created
    assert_equal "pro_restaurant", response.parsed_body["scenario"]
  end

  test "an invalid plan or a scenario of another plan is a 400" do
    open_demo(plan: "gold")
    assert_response :bad_request

    open_demo(plan: "basic", scenario: "pro_service")
    assert_response :bad_request
  end

  test "the contact is optional, and when given it is validated and saved" do
    open_demo(contact: { name: "Ana", email: "ana@ejemplo.mx", phone: "5512345678" })
    assert_response :created
    session = DemoSession.order(:id).last
    assert_equal [ "Ana", "ana@ejemplo.mx", "5512345678" ], session.values_at(:contact_name, :contact_email, :contact_phone)

    open_demo(contact: { email: "no-es-correo" })
    assert_response :unprocessable_entity

    open_demo(contact: { phone: "123" })
    assert_response :unprocessable_entity

    open_demo(contact: {})
    assert_response :created
  end

  test "answers 429 after the per-IP limit" do
    with_demo_env("DEMO_RATE_LIMIT" => 2) do
      Api::V1::DemoSessionsController::RATE_LIMIT_STORE.clear
      2.times { open_demo and assert_response :created }

      open_demo

      assert_response :too_many_requests
      assert_equal 429, response.parsed_body.dig("error", "status")
    end
  end

  test "answers 503 demo_busy when the active demos reach the cap" do
    with_demo_env("DEMO_MAX_ACTIVE" => 1) do
      open_demo
      assert_response :created

      open_demo

      assert_response :service_unavailable
      assert_equal "demo_busy", response.parsed_body.dig("error", "details", "code")
    end
  end

  test "answers 503 demo_busy when every provisioning slot is taken" do
    Demo::Provision.stub(:acquire_slot, nil) do
      open_demo
    end

    assert_response :service_unavailable
    assert_equal "demo_busy", response.parsed_body.dig("error", "details", "code")
    assert_equal 0, DemoSession.count
  end

  test "an ended or purged demo does not count against the cap" do
    with_demo_env("DEMO_MAX_ACTIVE" => 1) do
      open_demo
      DemoSession.last.update!(ended_at: Time.current, ended_reason: "left")

      open_demo

      assert_response :created
    end
  end

  test "creating a demo does not need authentication or a company header" do
    open_demo

    assert_response :created
    assert_not_equal 401, response.status
  end

  # ---------- Salir de la demo y aperturas ----------

  def demo_headers
    open_demo(plan: "pro", scenario: "pro_restaurant")
    body = response.parsed_body
    [ { "Authorization" => "Bearer #{body['token']}", "X-Company-Id" => body["company_id"].to_s }, body["company_id"] ]
  end

  test "finishing a demo records the reason, ends it and enqueues the purge" do
    headers, company_id = demo_headers

    assert_enqueued_with(job: Demo::PurgeJob, args: [ { company_id: company_id } ]) do
      delete "/api/v1/demo_sessions/current", headers: headers, params: { reason: "signup" }, as: :json
    end

    assert_response :no_content
    session = DemoSession.order(:id).last
    assert session.ended_at
    assert_equal "signup", session.ended_reason
  end

  test "the reason defaults to left and an unknown one is left too" do
    headers, = demo_headers
    delete "/api/v1/demo_sessions/current", headers: headers, params: { reason: "otro" }, as: :json

    assert_equal "left", DemoSession.order(:id).last.ended_reason
  end

  test "a user who is not in a demo cannot finish anything" do
    delete "/api/v1/demo_sessions/current", headers: auth_headers(users(:pro_co_owner), companies(:pro_co)), as: :json

    assert_response :forbidden
  end

  test "finishing works on the branch company of the enterprise demo" do
    open_demo(plan: "enterprise")
    body = response.parsed_body
    branch = Company.find(body["company_id"]).branches.first
    token = "Bearer #{body['token']}"

    delete "/api/v1/demo_sessions/current", headers: { "Authorization" => token, "X-Company-Id" => branch.id.to_s }, as: :json

    assert_response :no_content
    assert DemoSession.order(:id).last.ended_at
  end

  test "only a super admin lists the openings" do
    open_demo
    get "/api/v1/demo_sessions", headers: auth_headers(users(:pro_co_owner), companies(:pro_co))
    assert_response :forbidden

    get "/api/v1/demo_sessions", headers: auth_headers(users(:super_admin), companies(:pro_co))
    assert_response :ok
    assert_equal 1, response.parsed_body["info"]["total"]
  end

  test "the list shows invite and contact, filters, and never carries an IP" do
    invite, token = DemoInvite.issue!(plan: "basic", scenario: "basic_retail", label: "Abarrotes Lupita")
    open_demo(contact: { name: "Ana Pérez", email: "ana@ejemplo.mx" })
    post "/api/v1/demo_sessions", params: { invite_token: token }, as: :json
    open_demo(plan: "pro", scenario: "pro_service")
    headers = auth_headers(users(:super_admin), companies(:pro_co))

    get "/api/v1/demo_sessions", headers: headers
    assert_equal 3, response.parsed_body["results"].size
    assert_not_includes response.body, "remote_ip"
    assert_not_includes response.body, "user_agent"

    get "/api/v1/demo_sessions", params: { with_contact: "true" }, headers: headers
    results = response.parsed_body["results"]
    assert_equal 1, results.size
    assert_equal({ "name" => "Ana Pérez", "email" => "ana@ejemplo.mx", "phone" => nil }, results.first["contact"])

    get "/api/v1/demo_sessions", params: { demo_invite_id: invite.id }, headers: headers
    assert_equal [ { "id" => invite.id, "label" => "Abarrotes Lupita" } ], response.parsed_body["results"].map { |r| r["invite"] }

    get "/api/v1/demo_sessions", params: { plan: "pro" }, headers: headers
    assert_equal [ "pro" ], response.parsed_body["results"].map { |r| r["plan"] }

    get "/api/v1/demo_sessions", params: { search: "ana@" }, headers: headers
    assert_equal 1, response.parsed_body["results"].size
  end
end
