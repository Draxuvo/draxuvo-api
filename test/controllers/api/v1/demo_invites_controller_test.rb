require "test_helper"

# Contrato: specs/039-demo-por-plan/contracts/api.md (/demo_invites y apertura por invitación).
class Api::V1::DemoInvitesControllerTest < ActionDispatch::IntegrationTest
  setup do
    Api::V1::DemoSessionsController::RATE_LIMIT_STORE.clear
    @admin_headers = auth_headers(users(:super_admin), companies(:pro_co))
    @owner_headers = auth_headers(users(:pro_co_owner), companies(:pro_co))
  end

  def create_invite(**params)
    post "/api/v1/demo_invites", headers: @admin_headers, as: :json,
         params: { plan: "pro", scenario: "pro_restaurant", label: "Café La Plaza" }.merge(params)
  end

  test "only a super admin lists, creates and revokes" do
    get "/api/v1/demo_invites", headers: @owner_headers
    assert_response :forbidden
    post "/api/v1/demo_invites", headers: @owner_headers, params: { plan: "pro", scenario: "pro_service", label: "Ana" }, as: :json
    assert_response :forbidden
    invite, = DemoInvite.issue!(plan: "pro", scenario: "pro_service", label: "Ana")
    post "/api/v1/demo_invites/#{invite.id}/revoke", headers: @owner_headers
    assert_response :forbidden
  end

  test "creating returns the token and the link once; the list never shows them again" do
    create_invite

    assert_response :created
    body = response.parsed_body
    assert body["token"].present?
    assert_includes body["url"], "/es/demo/#{body['token']}"
    assert_equal [ "pro", "pro_restaurant", "Café La Plaza", "active", 0 ], body.values_at("plan", "scenario", "label", "status", "opens_count")
    assert_equal users(:super_admin).id, body.dig("created_by", "id")

    get "/api/v1/demo_invites", headers: @admin_headers
    listed = response.parsed_body["results"].first
    assert_equal body["id"], listed["id"]
    assert_not listed.key?("token")
    assert_not listed.key?("url")
  end

  test "the expiry is configurable between 1 and 60 days" do
    create_invite(expires_in_days: 3)
    assert_in_delta 3.days.from_now.to_i, Time.zone.parse(response.parsed_body["expires_at"]).to_i, 10

    create_invite(expires_in_days: 61)
    assert_response :bad_request
    create_invite(expires_in_days: 0)
    assert_response :bad_request
  end

  test "an invalid plan scenario pair or label is a 422" do
    create_invite(plan: "basic", scenario: "pro_service")
    assert_response :unprocessable_entity
    create_invite(label: "")
    assert_response :unprocessable_entity
  end

  test "the list filters by status, plan and search and counts the openings" do
    active, token = DemoInvite.issue!(plan: "pro", scenario: "pro_restaurant", label: "Café La Plaza")
    expired, = DemoInvite.issue!(plan: "basic", scenario: "basic_retail", label: "Abarrotes Lupita")
    expired.update_columns(expires_at: 1.day.ago)
    revoked, = DemoInvite.issue!(plan: "enterprise", scenario: "enterprise_restaurant", label: "Grupo Norte")
    revoked.revoke!
    post "/api/v1/demo_sessions", params: { invite_token: token }, as: :json
    assert_response :created

    get "/api/v1/demo_invites", params: { status: "active" }, headers: @admin_headers
    assert_equal [ active.id ], response.parsed_body["results"].map { |i| i["id"] }
    assert_equal 1, response.parsed_body["results"].first["opens_count"]
    assert response.parsed_body["results"].first["last_opened_at"].present?

    get "/api/v1/demo_invites", params: { status: "expired" }, headers: @admin_headers
    assert_equal [ expired.id ], response.parsed_body["results"].map { |i| i["id"] }
    get "/api/v1/demo_invites", params: { status: "revoked" }, headers: @admin_headers
    assert_equal [ revoked.id ], response.parsed_body["results"].map { |i| i["id"] }
    get "/api/v1/demo_invites", params: { plan: "basic" }, headers: @admin_headers
    assert_equal [ expired.id ], response.parsed_body["results"].map { |i| i["id"] }
    get "/api/v1/demo_invites", params: { search: "norte" }, headers: @admin_headers
    assert_equal [ revoked.id ], response.parsed_body["results"].map { |i| i["id"] }
  end

  test "revoking is idempotent" do
    invite, = DemoInvite.issue!(plan: "pro", scenario: "pro_service", label: "Ana")

    2.times do
      post "/api/v1/demo_invites/#{invite.id}/revoke", headers: @admin_headers
      assert_response :ok
      assert_equal "revoked", response.parsed_body["status"]
    end
  end

  test "resolve is public and tells the plan without creating anything" do
    _invite, token = DemoInvite.issue!(plan: "pro", scenario: "pro_restaurant", label: "Café La Plaza")

    assert_no_difference [ "Company.count", "DemoSession.count" ] do
      get "/api/v1/demo_invites/resolve", params: { token: token }
    end

    assert_response :ok
    assert_equal({ "plan" => "pro", "scenario" => "pro_restaurant" }, response.parsed_body)
    assert_not_includes response.body, "Café"
  end

  test "resolve answers 404 for an unknown token and 410 for an expired or revoked one" do
    get "/api/v1/demo_invites/resolve", params: { token: "no-existe" }
    assert_response :not_found

    expired, token = DemoInvite.issue!(plan: "pro", scenario: "pro_service", label: "Ana")
    expired.update_columns(expires_at: 1.minute.ago)
    get "/api/v1/demo_invites/resolve", params: { token: token }
    assert_response :gone
    assert_equal "invite_expired", response.parsed_body.dig("error", "details", "code")

    revoked, token = DemoInvite.issue!(plan: "pro", scenario: "pro_service", label: "Luis")
    revoked.revoke!
    get "/api/v1/demo_invites/resolve", params: { token: token }
    assert_response :gone
    assert_equal "invite_revoked", response.parsed_body.dig("error", "details", "code")
  end

  test "an invite opens the demo of its own plan, ignoring the plan and scenario in the body" do
    invite, token = DemoInvite.issue!(plan: "pro", scenario: "pro_restaurant", label: "Café La Plaza")

    post "/api/v1/demo_sessions", params: { invite_token: token, plan: "basic", scenario: "basic_retail", locale: "en" }, as: :json

    assert_response :created
    assert_equal [ "pro", "pro_restaurant" ], response.parsed_body.values_at("plan", "scenario")
    session = DemoSession.order(:id).last
    assert_equal invite, session.demo_invite
    assert_equal "en", session.locale
  end

  test "every opening creates a fresh demo and records it" do
    invite, token = DemoInvite.issue!(plan: "basic", scenario: "basic_retail", label: "Ana")

    2.times { post "/api/v1/demo_sessions", params: { invite_token: token }, as: :json and assert_response :created }

    assert_equal 2, invite.demo_sessions.count
    assert_equal 2, invite.demo_sessions.distinct.count(:company_id)
  end

  test "a revoked or expired token does not open a demo" do
    invite, token = DemoInvite.issue!(plan: "basic", scenario: "basic_retail", label: "Ana")
    invite.revoke!

    assert_no_difference "Company.count" do
      post "/api/v1/demo_sessions", params: { invite_token: token }, as: :json
    end
    assert_response :gone

    post "/api/v1/demo_sessions", params: { invite_token: "inventado" }, as: :json
    assert_response :not_found
  end
end
