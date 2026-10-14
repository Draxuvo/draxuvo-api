require "test_helper"

# Contrato: specs/002-rebrand-suscripciones/contracts/api.md (GET/PATCH/DELETE /subscription,
# POST /subscription/checkout, POST /subscription/portal). Stripe siempre se simula con stubs.
class Api::V1::SubscriptionsControllerTest < ActionDispatch::IntegrationTest
  BASE = "/api/v1/subscription".freeze

  PRO_MODULES = %w[employees attendance inventory work_orders tickets reports].freeze
  BASIC_MODULES = %w[employees attendance inventory].freeze

  # --- GET /subscription ------------------------------------------------------------------------

  test "show returns the subscription with the new fields for an owner" do
    get BASE, headers: auth_headers(users(:pro_co_owner))

    assert_response :ok
    body = json
    assert_equal subscriptions(:pro_co).id, body["id"]
    assert_equal "pro", body["plan"]
    assert_equal "monthly", body["billing_cycle"]
    assert_equal "active", body["status"]
    assert_equal false, body["cancel_at_period_end"]
    assert_equal 70_000, body["amount_cents"]
    assert_equal 11_200, body["iva_cents"]
    assert_equal 81_200, body["total_cents"]
    assert_equal PRO_MODULES, body["available_modules"]
    assert_equal PRO_MODULES, body["active_modules"]
    assert_equal true, body["active_access"]
    assert_in_delta 0.16, body["iva_rate"]
    %w[amount iva_amount total_with_iva trial_ends_at trial_days_remaining current_period_start
       current_period_end cancelled_at created_at].each do |key|
      assert body.key?(key), "missing #{key}"
    end
  end

  test "show is allowed with an expired trial" do
    get BASE, headers: auth_headers(users(:expired_co_owner))

    assert_response :ok
    assert_equal "expired", json["status"]
    assert_equal false, json["active_access"]
  end

  test "show lets the super admin read any company" do
    get BASE, headers: auth_headers(users(:super_admin), companies(:basic_co))

    assert_response :ok
    assert_equal "basic", json["plan"]
    assert_equal BASIC_MODULES, json["available_modules"]
  end

  # --- PATCH /subscription ----------------------------------------------------------------------

  test "update changes the plan during the trial without moving trial_ends_at" do
    subscription = subscriptions(:one)
    trial_ends_at = subscription.trial_ends_at

    patch BASE, params: { plan: "basic" }, headers: auth_headers(users(:one_owner)), as: :json

    assert_response :ok
    assert_equal "basic", json["plan"]
    assert_equal "trialing", json["status"]
    assert_equal BASIC_MODULES, json["available_modules"]

    subscription.reload
    assert_equal "basic", subscription.plan
    assert_equal "trialing", subscription.status
    assert_equal trial_ends_at.to_i, subscription.trial_ends_at.to_i
  end

  test "update rejects a paid subscription with not_trialing" do
    patch BASE, params: { plan: "enterprise" }, headers: auth_headers(users(:pro_co_owner)), as: :json

    assert_response :unprocessable_entity
    assert_error 422
    assert_equal "not_trialing", json.dig("error", "details", "code")
    assert_equal "pro", subscriptions(:pro_co).reload.plan
  end

  test "update rejects an expired subscription with not_trialing" do
    patch BASE, params: { plan: "basic" }, headers: auth_headers(users(:expired_co_owner)), as: :json

    assert_response :unprocessable_entity
    assert_equal "not_trialing", json.dig("error", "details", "code")
  end

  test "update rejects an unknown plan" do
    patch BASE, params: { plan: "starter" }, headers: auth_headers(users(:one_owner)), as: :json

    assert_response :bad_request
    assert_error 400
    assert_equal I18n.t("errors.subscription.invalid_plan"), json.dig("error", "details")
    assert_equal "pro", subscriptions(:one).reload.plan
  end

  # --- POST /subscription/checkout --------------------------------------------------------------

  test "checkout resolves the price by plan and billing cycle" do
    captured = with_checkout_stubs do
      post "#{BASE}/checkout",
           params: checkout_params(plan: "pro", billing_cycle: "annual"),
           headers: auth_headers(users(:expired_co_owner)), as: :json
    end

    assert_response :ok
    assert_equal "https://checkout.stripe.com/c/pay/cs_test_123", json["checkout_url"]
    assert_equal "subscription", captured[:mode].to_s
    assert_equal "price_draxuvo_pro_annual", captured.dig(:line_items, 0, :price)
    assert_equal "https://ui.test/es/suscripcion/exito", captured[:success_url]
    assert_equal "https://ui.test/es/suscripcion/cancelado", captured[:cancel_url]
  end

  test "checkout defaults the billing cycle to monthly" do
    captured = with_checkout_stubs do
      post "#{BASE}/checkout", params: checkout_params(plan: "basic"),
                               headers: auth_headers(users(:one_owner)), as: :json
    end

    assert_response :ok
    assert_equal "price_draxuvo_basic_monthly", captured.dig(:line_items, 0, :price)
  end

  test "checkout accepts the enterprise plan for an owner" do
    captured = with_checkout_stubs do
      post "#{BASE}/checkout",
           params: checkout_params(plan: "enterprise", billing_cycle: "monthly"),
           headers: auth_headers(users(:one_owner)), as: :json
    end

    assert_response :ok
    assert_equal "price_draxuvo_enterprise_monthly", captured.dig(:line_items, 0, :price)
  end

  test "checkout does not change the subscription before the webhook" do
    with_checkout_stubs do
      post "#{BASE}/checkout", params: checkout_params(plan: "pro", billing_cycle: "annual"),
                               headers: auth_headers(users(:expired_co_owner)), as: :json
    end

    assert_response :ok
    assert_equal "expired", subscriptions(:expired_co).reload.status
  end

  test "checkout rejects an invalid plan" do
    with_checkout_stubs do
      post "#{BASE}/checkout", params: checkout_params(plan: "business"),
                               headers: auth_headers(users(:one_owner)), as: :json
    end

    assert_response :bad_request
    assert_equal I18n.t("errors.subscription.invalid_plan"), json.dig("error", "details")
  end

  test "checkout rejects an invalid billing cycle" do
    with_checkout_stubs do
      post "#{BASE}/checkout", params: checkout_params(plan: "pro", billing_cycle: "weekly"),
                               headers: auth_headers(users(:one_owner)), as: :json
    end

    assert_response :bad_request
    assert_equal I18n.t("errors.subscription.invalid_plan"), json.dig("error", "details")
  end

  test "checkout requires success_url and cancel_url" do
    with_checkout_stubs do
      post "#{BASE}/checkout", params: { plan: "pro", billing_cycle: "monthly" },
                               headers: auth_headers(users(:one_owner)), as: :json
    end

    assert_response :bad_request
    assert_error 400
  end

  test "checkout reports a price missing in Stripe" do
    with_checkout_stubs(prices: []) do
      post "#{BASE}/checkout", params: checkout_params(plan: "pro", billing_cycle: "monthly"),
                               headers: auth_headers(users(:one_owner)), as: :json
    end

    assert_response :bad_request
    assert_equal I18n.t("errors.subscription.stripe_not_configured"), json.dig("error", "details")
  end

  test "checkout rejects a company with a paid subscription in force" do
    with_checkout_stubs do
      post "#{BASE}/checkout", params: checkout_params(plan: "enterprise", billing_cycle: "annual"),
                               headers: auth_headers(users(:pro_co_owner)), as: :json
    end

    assert_response :unprocessable_entity
    assert_equal "subscription_already_active", json.dig("error", "details", "code")
  end

  test "checkout rejects a past_due subscription with a Stripe id" do
    with_checkout_stubs do
      post "#{BASE}/checkout", params: checkout_params(plan: "pro", billing_cycle: "monthly"),
                               headers: auth_headers(users(:past_due_co_owner)), as: :json
    end

    assert_response :unprocessable_entity
    assert_equal "subscription_already_active", json.dig("error", "details", "code")
  end

  # --- POST /subscription/portal ----------------------------------------------------------------

  test "portal returns the Stripe billing portal url" do
    companies(:pro_co).update_column(:stripe_id, "cus_pro")
    captured = nil
    create = lambda do |params = {}, *_rest|
      captured = params.to_h.deep_symbolize_keys
      Stripe::StripeObject.construct_from(id: "bps_123", url: "https://billing.stripe.com/p/session/bps_123")
    end

    Stripe::BillingPortal::Session.stub(:create, create) do
      post "#{BASE}/portal", params: { return_url: "https://ui.test/es/suscripcion" },
                             headers: auth_headers(users(:pro_co_owner)), as: :json
    end

    assert_response :ok
    assert_equal "https://billing.stripe.com/p/session/bps_123", json["portal_url"]
    assert_equal "cus_pro", captured[:customer]
    assert_equal "https://ui.test/es/suscripcion", captured[:return_url]
  end

  test "portal requires return_url" do
    companies(:pro_co).update_column(:stripe_id, "cus_pro")

    Stripe::BillingPortal::Session.stub(:create, ->(*) { flunk "Stripe should not be called" }) do
      post "#{BASE}/portal", params: {}, headers: auth_headers(users(:pro_co_owner)), as: :json
    end

    assert_response :bad_request
    assert_error 400
  end

  test "portal rejects a company without a Stripe customer" do
    Stripe::BillingPortal::Session.stub(:create, ->(*) { flunk "Stripe should not be called" }) do
      post "#{BASE}/portal", params: { return_url: "https://ui.test/es/suscripcion" },
                             headers: auth_headers(users(:one_owner)), as: :json
    end

    assert_response :unprocessable_entity
    assert_equal "no_billing_account", json.dig("error", "details", "code")
  end

  # --- DELETE /subscription ---------------------------------------------------------------------

  test "destroy schedules the cancellation at period end and keeps access" do
    subscription = subscriptions(:pro_co)
    calls = []

    with_cancel_stubs(calls) do
      delete BASE, headers: auth_headers(users(:pro_co_owner))
    end

    assert_response :ok
    assert_equal true, json["cancel_at_period_end"]
    assert_equal "active", json["status"]
    assert_equal true, json["active_access"]

    assert_equal 1, calls.size, "expected one Stripe::Subscription.update call"
    assert_equal "sub_pro", calls.first[:id]
    assert_equal true, calls.first[:params][:cancel_at_period_end]

    subscription.reload
    assert subscription.cancel_at_period_end
    assert subscription.active?
    assert_nil subscription.cancelled_at
  end

  test "destroy works for the super admin on any company" do
    calls = []

    with_cancel_stubs(calls, stripe_id: "sub_basic", lookup_key: "draxuvo_basic_monthly") do
      delete BASE, headers: auth_headers(users(:super_admin), companies(:basic_co))
    end

    assert_response :ok
    assert_equal true, json["cancel_at_period_end"]
    assert_equal "sub_basic", calls.first[:id]
  end

  test "destroy returns 404 without a paid Stripe subscription" do
    Stripe::Subscription.stub(:update, ->(*) { flunk "Stripe should not be called" }) do
      Stripe::Subscription.stub(:cancel, ->(*) { flunk "Stripe should not cancel immediately" }) do
        delete BASE, headers: auth_headers(users(:one_owner))
      end
    end

    assert_response :not_found
    assert_error 404
    assert_equal "trialing", subscriptions(:one).reload.status
  end

  test "destroy returns 404 for an expired subscription" do
    Stripe::Subscription.stub(:update, ->(*) { flunk "Stripe should not be called" }) do
      delete BASE, headers: auth_headers(users(:expired_co_owner))
    end

    assert_response :not_found
  end

  # --- Roles ------------------------------------------------------------------------------------

  %i[pro_staff pro_manager].each do |role_user|
    test "#{role_user} gets 403 on every subscription action" do
      user = users(role_user)
      guard = ->(*) { flunk "Stripe should not be called" }

      Stripe::Checkout::Session.stub(:create, guard) do
        Stripe::BillingPortal::Session.stub(:create, guard) do
          Stripe::Subscription.stub(:update, guard) do
            get BASE, headers: auth_headers(user)
            assert_response :forbidden, "GET"
            assert_error 403

            patch BASE, params: { plan: "basic" }, headers: auth_headers(user), as: :json
            assert_response :forbidden, "PATCH"

            post "#{BASE}/checkout", params: checkout_params(plan: "pro"), headers: auth_headers(user), as: :json
            assert_response :forbidden, "checkout"

            post "#{BASE}/portal", params: { return_url: "https://ui.test/es/suscripcion" },
                                   headers: auth_headers(user), as: :json
            assert_response :forbidden, "portal"

            delete BASE, headers: auth_headers(user)
            assert_response :forbidden, "DELETE"
          end
        end
      end

      assert_equal "pro", subscriptions(:pro_co).reload.plan
      assert_not subscriptions(:pro_co).cancel_at_period_end
    end
  end

  private

  def json
    JSON.parse(response.body)
  end

  def assert_error(status)
    assert_equal status, json.dig("error", "status")
    assert json["error"].key?("message")
    assert json["error"].key?("details")
  end

  def checkout_params(plan:, billing_cycle: nil)
    params = {
      plan: plan,
      success_url: "https://ui.test/es/suscripcion/exito",
      cancel_url: "https://ui.test/es/suscripcion/cancelado"
    }
    params[:billing_cycle] = billing_cycle if billing_cycle
    params
  end

  ALL_LOOKUP_KEYS = %w[basic pro enterprise].product(%w[monthly annual]).map { |p, c| "draxuvo_#{p}_#{c}" }.freeze

  # Simula Stripe::Price.list (por lookup_keys), Stripe::Customer.create y
  # Stripe::Checkout::Session.create. Devuelve los parámetros con que se creó la sesión.
  def with_checkout_stubs(prices: ALL_LOOKUP_KEYS)
    captured = nil

    price_list = lambda do |params = {}, *_rest|
      requested = Array(params.to_h.with_indifferent_access[:lookup_keys]).map(&:to_s)
      keys = requested.empty? ? prices : prices & requested
      Stripe::ListObject.construct_from(
        object: "list",
        data: keys.map { |key| { id: "price_#{key}", object: "price", lookup_key: key, active: true } }
      )
    end
    customer_create = ->(*) { Stripe::StripeObject.construct_from(id: "cus_new", object: "customer") }
    session_create = lambda do |params = {}, *_rest|
      captured = params.to_h.deep_symbolize_keys
      Stripe::StripeObject.construct_from(id: "cs_test_123", object: "checkout.session",
                                          url: "https://checkout.stripe.com/c/pay/cs_test_123")
    end

    Stripe::Price.stub(:list, price_list) do
      Stripe::Customer.stub(:create, customer_create) do
        Stripe::Checkout::Session.stub(:create, session_create) do
          yield
        end
      end
    end

    captured
  end

  # Simula la cancelación programada en Stripe. `calls` recibe cada Stripe::Subscription.update.
  def with_cancel_stubs(calls, stripe_id: "sub_pro", lookup_key: "draxuvo_pro_monthly")
    period_start = 5.days.ago.to_i
    period_end = 25.days.from_now.to_i
    stripe_sub = Stripe::Subscription.construct_from(
      id: stripe_id,
      object: "subscription",
      status: "active",
      cancel_at_period_end: true,
      current_period_start: period_start,
      current_period_end: period_end,
      items: {
        object: "list",
        data: [ {
          id: "si_123",
          object: "subscription_item",
          current_period_start: period_start,
          current_period_end: period_end,
          price: { id: "price_#{lookup_key}", object: "price", lookup_key: lookup_key }
        } ]
      }
    )

    update = lambda do |id, params = {}, *_rest|
      calls << { id: id, params: params.to_h.deep_symbolize_keys }
      stripe_sub
    end

    Stripe::Subscription.stub(:update, update) do
      Stripe::Subscription.stub(:retrieve, ->(*) { stripe_sub }) do
        Stripe::Subscription.stub(:cancel, ->(*) { flunk "Stripe should not cancel immediately" }) do
          yield
        end
      end
    end
  end
end
