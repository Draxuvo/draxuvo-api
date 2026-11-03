require "test_helper"

class Api::V1::SubscriptionAddonsControllerTest < ActionDispatch::IntegrationTest
  BASE = "/api/v1/subscription".freeze

  setup do
    @company = companies(:basic_co)
    @subscription = subscriptions(:basic_co)
    @owner = users(:basic_co_owner)
    @headers = auth_headers(@owner, @company)
    @created = []
    @deleted = []
  end

  def json = response.parsed_body

  def code = json.dig("error", "details", "code")

  def call(verb, path, params: {}, headers: @headers, **stubs)
    with_memory_cache do
      with_addon_stubs(created: @created, deleted: @deleted, **stubs) { public_send(verb, "#{BASE}#{path}", params: params, headers: headers, as: :json) }
    end
  end

  # --- contratar ---

  test "POST addons contracts the module and answers the subscription with the breakdown" do
    call(:post, "/addons", params: { module: "pos" })

    assert_response :created
    assert_equal 39_900, json["amount_cents"]
    assert_equal 19_900, json["addons_cents"]
    assert_equal [ "pos" ], json["addons"].map { |a| a["module"] }
    assert_equal "active", json["addons"].first["status"]
    assert_includes json["active_modules"], "pos"
    assert_equal "addon", json["module_sources"]["pos"]
    assert_equal "plan", json["module_sources"]["inventory"]
    assert_equal 9_568, json["iva_cents"]
    assert_equal 69_368, json["total_cents"]
    assert_in_delta 693.68, json["total_with_iva"], 0.001
  end

  test "an administrator can contract it but staff cannot" do
    admin = create_member(@company, role: :admin)
    call(:post, "/addons", params: { module: "pos" }, headers: auth_headers(admin, @company))
    assert_response :created

    staff = create_member(@company, role: :staff)
    call(:post, "/addons", params: { module: "pos" }, headers: auth_headers(staff, @company))
    assert_response :forbidden
  end

  test "a failed prorated charge answers 402 and nothing is activated" do
    call(:post, "/addons", params: { module: "pos" }, charge_error: true)

    assert_response :payment_required
    assert_equal "addon_payment_failed", code
    assert_not @company.reload.module_active?(:pos)
  end

  test "errors carry their code" do
    call(:post, "/addons", params: { module: "inventory" })
    assert_response :unprocessable_entity
    assert_equal "unknown_addon", code

    call(:post, "/addons", params: {})
    assert_response :bad_request

    call(:post, "/addons", params: { module: "pos" }, headers: auth_headers(users(:one_owner), companies(:one)))
    assert_response :unprocessable_entity
    assert_equal "subscription_not_paid", code
  end

  test "already contracted" do
    call(:post, "/addons", params: { module: "pos" })
    call(:post, "/addons", params: { module: "pos" })
    assert_response :unprocessable_entity
    assert_equal "addon_already_active", code
  end

  test "a branch cannot change the billing" do
    branch = Company.create!(name: "Sucursal", parent: @company)
    UserCompany.create!(user: @owner, company: branch, role: :owner)
    call(:post, "/addons", params: { module: "pos" }, headers: auth_headers(@owner, branch))
    assert_response :unprocessable_entity
    assert_equal "billing_managed_by_parent", code
    assert_empty @created
  end

  test "a demo company cannot pay" do
    Api::V1::DemoSessionsController::RATE_LIMIT_STORE.clear
    demo = Demo::Provision.call(plan: "basic", scenario: "basic_retail", locale: "es")
    call(:post, "/addons", params: { module: "pos" }, headers: auth_headers(demo.user, demo.company))

    assert_response :forbidden
    assert_equal "demo_restricted", code
    assert_empty @created
  end

  test "an expired subscription can still be looked at but not contracted" do
    call(:post, "/addons", params: { module: "pos" }, headers: auth_headers(users(:expired_co_owner), companies(:expired_co)))
    assert_response :unprocessable_entity
    assert_equal "subscription_not_paid", code
  end

  test "requires authentication" do
    post "#{BASE}/addons", params: { module: "pos" }, as: :json
    assert_response :unauthorized
  end

  # --- baja y reactivación ---

  test "DELETE addons/:module schedules the end and keeps the module until then" do
    grant_addon!(@company, :pos)
    call(:delete, "/addons/pos")

    assert_response :ok
    assert_equal "ending", json["addons"].first["status"]
    assert_not_nil json["addons"].first["ends_at"]
    assert_includes json["active_modules"], "pos"
    assert_equal 19_900, json["addons_cents"]
  end

  test "an add-on already over does not appear nor count" do
    grant_addon!(@company, :pos, ends_at: 1.hour.ago)
    get BASE, headers: @headers

    assert_response :ok
    assert_empty json["addons"]
    assert_equal 0, json["addons_cents"]
    assert_not_includes json["active_modules"], "pos"
    assert_equal 6_384, json["iva_cents"]
  end

  test "DELETE errors" do
    call(:delete, "/addons/pos")
    assert_response :not_found
    assert_equal "addon_not_found", code

    grant_addon!(@company, :pos)
    call(:delete, "/addons/pos")
    call(:delete, "/addons/pos")
    assert_response :unprocessable_entity
    assert_equal "addon_already_ending", code
  end

  test "POST addons/:module/reactivate undoes a pending end" do
    grant_addon!(@company, :pos, ends_at: 5.days.from_now)
    call(:post, "/addons/pos/reactivate")

    assert_response :ok
    assert_equal "active", json["addons"].first["status"]
    assert_nil json["addons"].first["ends_at"]
  end

  test "reactivate without a pending end is rejected" do
    grant_addon!(@company, :pos)
    call(:post, "/addons/pos/reactivate")
    assert_response :unprocessable_entity
    assert_equal "addon_not_ending", code
  end

  # --- checkout y portal ---

  test "checkout accepts the add-ons of the trial" do
    captured = with_memory_cache do
      with_checkout_stubs do
        post "#{BASE}/checkout", params: { plan: "pro", billing_cycle: "monthly", addons: [ "pos" ], success_url: "https://a.test/ok", cancel_url: "https://a.test/no" },
                                 headers: auth_headers(users(:one_owner), companies(:one)), as: :json
      end
    end

    assert_response :ok
    assert_equal 2, captured[:line_items].size
  end
end
