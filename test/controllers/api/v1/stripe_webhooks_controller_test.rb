require "test_helper"

# T018 · R11, R12, contracts/api.md (POST /stripe/webhooks). FR-010, FR-011, SC-004, SC-005.
# Stripe nunca se llama por red: la firma se genera con el secreto de prueba y
# Stripe::Subscription.retrieve se reemplaza con un stub.
class Api::V1::StripeWebhooksControllerTest < ActionDispatch::IntegrationTest
  SECRET = "whsec_test_draxuvo".freeze
  URL = "/api/v1/stripe/webhooks".freeze

  setup do
    @previous_secret = ENV["STRIPE_WEBHOOK_SECRET"]
    ENV["STRIPE_WEBHOOK_SECRET"] = SECRET
    @event_seq = 0
    @retrieve_calls = 0
  end

  teardown do
    if @previous_secret.nil?
      ENV.delete("STRIPE_WEBHOOK_SECRET")
    else
      ENV["STRIPE_WEBHOOK_SECRET"] = @previous_secret
    end
  end

  # --- helpers -------------------------------------------------------------

  def sign(payload, secret: SECRET, at: Time.now)
    signature = Stripe::Webhook::Signature.compute_signature(at, payload, secret)
    Stripe::Webhook::Signature.generate_header(at, signature)
  end

  def event_payload(type, object, id: nil)
    @event_seq += 1
    {
      id: id || "evt_test_#{@event_seq}_#{SecureRandom.hex(4)}",
      object: "event",
      api_version: Stripe::ApiVersion::CURRENT,
      created: Time.now.to_i,
      type: type,
      data: { object: object }
    }.to_json
  end

  def post_webhook(payload, signature: :valid)
    headers = { "Content-Type" => "application/json" }
    headers["Stripe-Signature"] = signature == :valid ? sign(payload) : signature if signature
    post URL, params: payload, headers: headers
  end

  # Suscripción de Stripe como la devuelve la API (versión acacia), con el periodo también en el item.
  def stripe_sub_hash(id:, status:, lookup_key:, cancel_at_period_end: false, customer: "cus_test",
                      period_start: 1.day.ago, period_end: 29.days.from_now, metadata: {})
    {
      id: id,
      object: "subscription",
      customer: customer,
      status: status,
      cancel_at_period_end: cancel_at_period_end,
      canceled_at: (status == "canceled" ? Time.now.to_i : nil),
      current_period_start: period_start.to_i,
      current_period_end: period_end.to_i,
      metadata: metadata,
      items: {
        object: "list",
        data: [
          {
            id: "si_#{id}",
            object: "subscription_item",
            current_period_start: period_start.to_i,
            current_period_end: period_end.to_i,
            price: { id: "price_#{lookup_key}", object: "price", lookup_key: lookup_key }
          }
        ]
      }
    }
  end

  def stripe_sub(**attrs)
    Stripe::Subscription.construct_from(stripe_sub_hash(**attrs))
  end

  # Stub de Stripe::Subscription.retrieve. `source` es una Stripe::Subscription o un bloque que la
  # devuelve según el id pedido.
  def with_stripe(source = nil, &blk)
    retriever = lambda do |arg, *_rest, **_opts|
      @retrieve_calls += 1
      id = arg.is_a?(Hash) ? (arg[:id] || arg["id"]) : arg
      source.respond_to?(:call) ? source.call(id.to_s) : source
    end
    Stripe::Subscription.stub(:retrieve, retriever, &blk)
  end

  def refuse_stripe(&blk)
    Stripe::Subscription.stub(:retrieve, ->(*) { flunk "no debe consultar Stripe" }, &blk)
  end

  def json
    JSON.parse(response.body)
  end

  def assert_bad_request
    assert_response :bad_request
    assert_equal 400, json.dig("error", "status")
  end

  # --- autenticación y firma (FR-010) --------------------------------------

  test "no exige Authorization y responde 200 con firma válida" do
    sub = subscriptions(:pro_co)
    current = stripe_sub(id: "sub_pro", status: "active", lookup_key: "draxuvo_pro_monthly")
    payload = event_payload("customer.subscription.updated", stripe_sub_hash(id: "sub_pro", status: "active", lookup_key: "draxuvo_pro_monthly"))

    with_stripe(current) { post_webhook(payload) }

    assert_response :ok
    assert_equal({ "received" => true }, json)
    assert sub.reload.active?
  end

  test "sin STRIPE_WEBHOOK_SECRET responde 400 y no procesa nada" do
    ENV.delete("STRIPE_WEBHOOK_SECRET")
    payload = event_payload("customer.subscription.updated", stripe_sub_hash(id: "sub_pro", status: "canceled", lookup_key: "draxuvo_pro_monthly"))

    assert_no_difference -> { StripeEvent.count } do
      refuse_stripe { post_webhook(payload, signature: sign(payload)) }
    end

    assert_bad_request
    assert subscriptions(:pro_co).reload.active?
  end

  test "el secreto se lee en cada request, no al cargar la clase" do
    ENV["STRIPE_WEBHOOK_SECRET"] = "whsec_rotado"
    payload = event_payload("customer.subscription.updated", stripe_sub_hash(id: "sub_pro", status: "past_due", lookup_key: "draxuvo_pro_monthly"))
    current = stripe_sub(id: "sub_pro", status: "past_due", lookup_key: "draxuvo_pro_monthly")

    with_stripe(current) { post_webhook(payload, signature: sign(payload, secret: "whsec_rotado")) }

    assert_response :ok
    assert subscriptions(:pro_co).reload.past_due?
  end

  test "firma inválida responde 400 y no procesa nada" do
    payload = event_payload("customer.subscription.updated", stripe_sub_hash(id: "sub_pro", status: "canceled", lookup_key: "draxuvo_pro_monthly"))

    assert_no_difference -> { StripeEvent.count } do
      refuse_stripe { post_webhook(payload, signature: sign(payload, secret: "whsec_otro")) }
    end

    assert_bad_request
    assert subscriptions(:pro_co).reload.active?
  end

  test "sin header Stripe-Signature responde 400" do
    payload = event_payload("customer.subscription.updated", stripe_sub_hash(id: "sub_pro", status: "canceled", lookup_key: "draxuvo_pro_monthly"))

    assert_no_difference -> { StripeEvent.count } do
      refuse_stripe { post_webhook(payload, signature: nil) }
    end

    assert_bad_request
    assert subscriptions(:pro_co).reload.active?
  end

  test "payload firmado que no es JSON responde 400" do
    payload = "esto no es json"

    refuse_stripe { post_webhook(payload) }

    assert_bad_request
  end

  # --- idempotencia (FR-011, SC-005) ---------------------------------------

  test "el mismo evento dos veces se aplica una sola vez" do
    sub = subscriptions(:pro_co)
    payload = event_payload("customer.subscription.updated",
                            stripe_sub_hash(id: "sub_pro", status: "active", lookup_key: "draxuvo_pro_annual"),
                            id: "evt_duplicado")
    responses = [
      stripe_sub(id: "sub_pro", status: "active", lookup_key: "draxuvo_pro_annual"),
      stripe_sub(id: "sub_pro", status: "past_due", lookup_key: "draxuvo_basic_monthly", cancel_at_period_end: true)
    ]

    with_stripe(->(_id) { responses.shift }) do
      assert_difference -> { StripeEvent.count }, 1 do
        post_webhook(payload)
        assert_response :ok
        post_webhook(payload)
        assert_response :ok
      end
    end

    assert_equal 1, @retrieve_calls
    assert_equal 1, StripeEvent.where(stripe_event_id: "evt_duplicado").count
    assert_equal "customer.subscription.updated", StripeEvent.find_by!(stripe_event_id: "evt_duplicado").event_type
    sub.reload
    assert sub.active?
    assert_equal "annual", sub.billing_cycle
    assert_not sub.cancel_at_period_end
  end

  # --- orden irrelevante (SC-004) ------------------------------------------

  test "eventos fuera de orden dejan el estado de la suscripción leída de Stripe" do
    sub = subscriptions(:pro_co)
    period_end = 40.days.from_now.change(usec: 0)
    current = stripe_sub(id: "sub_pro", status: "active", lookup_key: "draxuvo_enterprise_monthly",
                         cancel_at_period_end: true, period_end: period_end)

    newer = event_payload("customer.subscription.updated",
                          stripe_sub_hash(id: "sub_pro", status: "active", lookup_key: "draxuvo_enterprise_monthly", cancel_at_period_end: true))
    older = event_payload("invoice.payment_failed",
                          { id: "in_viejo", object: "invoice", customer: "cus_test", subscription: "sub_pro",
                            parent: { type: "subscription_details", subscription_details: { subscription: "sub_pro" } } })
    stale = event_payload("customer.subscription.updated",
                          stripe_sub_hash(id: "sub_pro", status: "past_due", lookup_key: "draxuvo_pro_monthly"))

    with_stripe(current) do
      [ newer, older, stale ].each do |payload|
        post_webhook(payload)
        assert_response :ok
      end
    end

    sub.reload
    assert sub.active?
    assert_equal "enterprise", sub.plan
    assert sub.cancel_at_period_end
    assert_in_delta period_end, sub.current_period_end, 1.second
  end

  # --- mapeo de estados (R12) ----------------------------------------------

  test "mapea los estados de Stripe a los locales" do
    sub = subscriptions(:pro_co)
    {
      "trialing" => "trialing",
      "active" => "active",
      "past_due" => "past_due",
      "unpaid" => "past_due",
      "canceled" => "cancelled",
      "incomplete_expired" => "cancelled"
    }.each do |stripe_status, local_status|
      sub.update_columns(status: Subscription.statuses[:active], cancelled_at: nil)
      current = stripe_sub(id: "sub_pro", status: stripe_status, lookup_key: "draxuvo_pro_monthly")
      payload = event_payload("customer.subscription.updated",
                              stripe_sub_hash(id: "sub_pro", status: stripe_status, lookup_key: "draxuvo_pro_monthly"))

      with_stripe(current) { post_webhook(payload) }

      assert_response :ok
      assert_equal local_status, sub.reload.status, "Stripe #{stripe_status} debe quedar #{local_status}"
    end
  end

  test "canceled llena cancelled_at" do
    sub = subscriptions(:pro_co)
    current = stripe_sub(id: "sub_pro", status: "canceled", lookup_key: "draxuvo_pro_monthly")
    payload = event_payload("customer.subscription.deleted",
                            stripe_sub_hash(id: "sub_pro", status: "canceled", lookup_key: "draxuvo_pro_monthly"))

    with_stripe(current) { post_webhook(payload) }

    assert_response :ok
    assert sub.reload.cancelled?
    assert_not_nil sub.cancelled_at
  end

  test "incomplete deja el estado anterior" do
    sub = subscriptions(:past_due_co)
    current = stripe_sub(id: "sub_past_due", status: "incomplete", lookup_key: "draxuvo_pro_monthly")
    payload = event_payload("customer.subscription.updated",
                            stripe_sub_hash(id: "sub_past_due", status: "incomplete", lookup_key: "draxuvo_pro_monthly"))

    with_stripe(current) { post_webhook(payload) }

    assert_response :ok
    assert sub.reload.past_due?
  end

  test "un estado desconocido no cae en expired" do
    sub = subscriptions(:pro_co)
    current = stripe_sub(id: "sub_pro", status: "paused", lookup_key: "draxuvo_pro_monthly")
    payload = event_payload("customer.subscription.updated",
                            stripe_sub_hash(id: "sub_pro", status: "paused", lookup_key: "draxuvo_pro_monthly"))

    with_stripe(current) { post_webhook(payload) }

    assert_response :ok
    assert sub.reload.active?
  end

  test "invoice.payment_failed vuelve a leer la suscripción y la deja en past_due" do
    sub = subscriptions(:pro_co)
    current = stripe_sub(id: "sub_pro", status: "past_due", lookup_key: "draxuvo_pro_monthly")
    payload = event_payload("invoice.payment_failed",
                            { id: "in_fallido", object: "invoice", customer: "cus_test", subscription: "sub_pro",
                              parent: { type: "subscription_details", subscription_details: { subscription: "sub_pro" } } })

    with_stripe(current) { post_webhook(payload) }

    assert_response :ok
    assert sub.reload.past_due?
  end

  # --- plan y ciclo desde lookup_key, cancel_at_period_end -----------------

  test "plan, ciclo y monto salen del lookup_key del precio" do
    sub = subscriptions(:pro_co)
    current = stripe_sub(id: "sub_pro", status: "active", lookup_key: "draxuvo_enterprise_annual")
    payload = event_payload("customer.subscription.updated",
                            stripe_sub_hash(id: "sub_pro", status: "active", lookup_key: "draxuvo_enterprise_annual"))

    with_stripe(current) { post_webhook(payload) }

    assert_response :ok
    sub.reload
    assert_equal "enterprise", sub.plan
    assert_equal "annual", sub.billing_cycle
    assert_equal 1_299_000, sub.amount_cents
    assert_equal "draxuvo_enterprise_annual", sub.stripe_price_lookup_key
  end

  test "bajar de plan por el portal llega como basic mensual" do
    sub = subscriptions(:enterprise_co)
    current = stripe_sub(id: "sub_enterprise", status: "active", lookup_key: "draxuvo_basic_monthly")
    payload = event_payload("customer.subscription.updated",
                            stripe_sub_hash(id: "sub_enterprise", status: "active", lookup_key: "draxuvo_basic_monthly"))

    with_stripe(current) { post_webhook(payload) }

    assert_response :ok
    sub.reload
    assert_equal "basic", sub.plan
    assert_equal "monthly", sub.billing_cycle
    assert_equal 39_900, sub.amount_cents
  end

  test "un lookup_key desconocido no toca el plan" do
    sub = subscriptions(:pro_co)
    current = stripe_sub(id: "sub_pro", status: "active", lookup_key: "grupo_bothi_business")
    payload = event_payload("customer.subscription.updated",
                            stripe_sub_hash(id: "sub_pro", status: "active", lookup_key: "grupo_bothi_business"))

    with_stripe(current) { post_webhook(payload) }

    assert_response :ok
    sub.reload
    assert_equal Subscription.plans.key(1), sub.plan
    assert_equal "monthly", sub.billing_cycle
    assert_equal 70_000, sub.amount_cents
  end

  test "copia cancel_at_period_end y conserva el estado" do
    sub = subscriptions(:pro_co)
    period_end = 25.days.from_now.change(usec: 0)
    current = stripe_sub(id: "sub_pro", status: "active", lookup_key: "draxuvo_pro_monthly",
                         cancel_at_period_end: true, period_end: period_end)
    payload = event_payload("customer.subscription.updated",
                            stripe_sub_hash(id: "sub_pro", status: "active", lookup_key: "draxuvo_pro_monthly", cancel_at_period_end: true))

    with_stripe(current) { post_webhook(payload) }

    assert_response :ok
    sub.reload
    assert sub.active?
    assert sub.cancel_at_period_end
    assert_in_delta period_end, sub.current_period_end, 1.second

    reactivated = stripe_sub(id: "sub_pro", status: "active", lookup_key: "draxuvo_pro_monthly", cancel_at_period_end: false)
    payload = event_payload("customer.subscription.updated",
                            stripe_sub_hash(id: "sub_pro", status: "active", lookup_key: "draxuvo_pro_monthly"))

    with_stripe(reactivated) { post_webhook(payload) }

    assert_response :ok
    assert_not sub.reload.cancel_at_period_end
  end

  # --- checkout y eventos sin efecto ---------------------------------------

  test "checkout.session.completed activa la suscripción de la empresa en prueba" do
    company = companies(:one)
    current = stripe_sub(id: "sub_nuevo", status: "active", lookup_key: "draxuvo_pro_annual",
                         customer: "cus_nuevo", metadata: { company_id: company.id.to_s })
    session = {
      id: "cs_test_1", object: "checkout.session", mode: "subscription", status: "complete",
      customer: "cus_nuevo", subscription: "sub_nuevo", client_reference_id: company.id.to_s,
      metadata: { company_id: company.id.to_s, plan: "pro", billing_cycle: "annual" }
    }
    payload = event_payload("checkout.session.completed", session)

    with_stripe(current) { post_webhook(payload) }

    assert_response :ok
    sub = company.reload.subscription
    assert sub.active?
    assert_equal "sub_nuevo", sub.stripe_subscription_id
    assert_equal "annual", sub.billing_cycle
    assert_equal 700_000, sub.amount_cents
    assert_equal 1, Subscription.where(company: company).count
  end

  test "un tipo de evento no atendido responde 200 sin efectos" do
    payload = event_payload("customer.created", { id: "cus_x", object: "customer" })

    refuse_stripe { post_webhook(payload) }

    assert_response :ok
    assert subscriptions(:pro_co).reload.active?
  end

  test "una suscripción de Stripe sin registro local responde 200 sin crear nada" do
    current = stripe_sub(id: "sub_huerfana", status: "active", lookup_key: "draxuvo_pro_monthly")
    payload = event_payload("customer.subscription.updated",
                            stripe_sub_hash(id: "sub_huerfana", status: "active", lookup_key: "draxuvo_pro_monthly"))

    assert_no_difference -> { Subscription.count } do
      with_stripe(current) { post_webhook(payload) }
    end

    assert_response :ok
  end
end
