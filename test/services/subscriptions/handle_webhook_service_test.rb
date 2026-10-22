require "test_helper"

class Subscriptions::HandleWebhookServiceTest < ActiveSupport::TestCase
  def event(type, object, id: "evt_#{SecureRandom.hex(6)}")
    Stripe::Event.construct_from(id: id, object: "event", type: type, data: { object: object })
  end

  def stripe_sub(**attrs)
    Stripe::Subscription.construct_from(stripe_sub_hash(**attrs))
  end

  def handle(event, stripe_subscription = nil, &block)
    retrieve = block || ->(*) { stripe_subscription }
    Stripe::Subscription.stub(:retrieve, retrieve) { Subscriptions::HandleWebhookService.new(event).call }
  end

  test "records the event and returns true" do
    ev = event("customer.subscription.updated", { "id" => "sub_pro" })
    result = handle(ev, stripe_sub(id: "sub_pro", status: "past_due", lookup_key: "draxuvo_pro_monthly"))
    assert result
    record = StripeEvent.find_by!(stripe_event_id: ev.id)
    assert_equal "customer.subscription.updated", record.event_type
    assert subscriptions(:pro_co).reload.past_due?
  end

  test "a repeated event returns false and does not apply effects again" do
    ev = event("customer.subscription.updated", { "id" => "sub_pro" }, id: "evt_dup")
    sub = stripe_sub(id: "sub_pro", status: "past_due", lookup_key: "draxuvo_pro_monthly")
    assert handle(ev, sub)
    calls = 0
    assert_equal false, handle(ev) { calls += 1 }
    assert_equal 0, calls
    assert_equal 1, StripeEvent.where(stripe_event_id: "evt_dup").count
  end

  test "checkout completed links the Stripe subscription to the company and syncs it" do
    company = companies(:one)
    session = { "id" => "cs_1", "subscription" => "sub_new", "metadata" => { "company_id" => company.id.to_s } }
    handle(event("checkout.session.completed", session),
           stripe_sub(id: "sub_new", status: "active", lookup_key: "draxuvo_enterprise_annual"))
    subscription = company.subscription.reload
    assert_equal "sub_new", subscription.stripe_subscription_id
    assert subscription.active?
    assert subscription.enterprise?
  end

  test "checkout completed falls back to client_reference_id and an expanded subscription" do
    company = companies(:two)
    session = { "id" => "cs_2", "subscription" => { "id" => "sub_exp" }, "client_reference_id" => company.id.to_s }
    handle(event("checkout.session.completed", session),
           stripe_sub(id: "sub_exp", status: "active", lookup_key: "draxuvo_basic_monthly"))
    assert_equal "sub_exp", company.subscription.reload.stripe_subscription_id
  end

  test "checkout completed creates a local subscription when the company has none" do
    company = Company.create!(name: "Sin Suscripcion", parent: companies(:enterprise_co))
    assert_nil company.subscription
    session = { "id" => "cs_3", "subscription" => "sub_branch", "metadata" => { "company_id" => company.id.to_s } }
    handle(event("checkout.session.completed", session),
           stripe_sub(id: "sub_branch", status: "active", lookup_key: "draxuvo_basic_monthly"))
    subscription = company.reload.subscription
    assert_equal "sub_branch", subscription.stripe_subscription_id
    assert subscription.active?
    assert subscription.basic?
  end

  test "checkout completed without subscription or company is ignored" do
    [
      { "id" => "cs_4", "metadata" => { "company_id" => companies(:one).id.to_s } },
      { "id" => "cs_5", "subscription" => "sub_x" },
      { "id" => "cs_6", "subscription" => "sub_x", "metadata" => { "company_id" => "0" } }
    ].each do |session|
      assert handle(event("checkout.session.completed", session)) { flunk "should not call Stripe" }
    end
  end

  test "invoice events sync the subscription found in the invoice" do
    handle(event("invoice.payment_failed", { "id" => "in_1", "subscription" => "sub_pro" }),
           stripe_sub(id: "sub_pro", status: "past_due", lookup_key: "draxuvo_pro_monthly"))
    assert subscriptions(:pro_co).reload.past_due?
  end

  test "invoice events read the subscription from the parent details" do
    invoice = { "id" => "in_2", "parent" => { "subscription_details" => { "subscription" => "sub_past_due" } } }
    handle(event("invoice.paid", invoice), stripe_sub(id: "sub_past_due", status: "active", lookup_key: "draxuvo_pro_monthly"))
    assert subscriptions(:past_due_co).reload.active?
  end

  test "an invoice without a subscription is ignored" do
    assert handle(event("invoice.paid", { "id" => "in_3" })) { flunk "should not call Stripe" }
  end

  test "unrelated events are recorded and ignored" do
    ev = event("customer.created", { "id" => "cus_1" })
    assert handle(ev) { flunk "should not call Stripe" }
    assert StripeEvent.exists?(stripe_event_id: ev.id)
  end

  test "if the sync fails the event is rolled back so Stripe can retry" do
    ev = event("customer.subscription.updated", { "id" => "sub_pro" }, id: "evt_retry")
    assert_raises(Stripe::APIConnectionError) do
      handle(ev) { raise Stripe::APIConnectionError, "sin red" }
    end
    assert_not StripeEvent.exists?(stripe_event_id: "evt_retry")
    assert handle(ev, stripe_sub(id: "sub_pro", status: "active", lookup_key: "draxuvo_pro_monthly"))
    assert StripeEvent.exists?(stripe_event_id: "evt_retry")
  end

  # --- spec 031: pagos fallidos ---

  def invoice(reason, subscription: "sub_pro", url: "https://invoice.stripe.com/i/x")
    { "id" => "in_#{SecureRandom.hex(4)}", "subscription" => subscription, "billing_reason" => reason, "hosted_invoice_url" => url }
  end

  test "a failed plan change invoice suspends the company at once with the invoice url" do
    ResendMailer.stub(:subscription_notice, { "id" => "email_1" }) do
      handle(event("invoice.payment_failed", invoice("subscription_update")),
             stripe_sub(id: "sub_pro", status: "past_due", lookup_key: "draxuvo_enterprise_monthly"))
    end

    subscription = subscriptions(:pro_co).reload
    assert subscription.suspended?
    assert_equal "plan_change", subscription.suspension_reason
    assert_equal "https://invoice.stripe.com/i/x", subscription.pending_invoice_url
    assert subscription.enterprise?
    assert_equal "suspended", subscription.subscription_changes.last.kind
  end

  test "a failed renewal invoice leaves past_due with the grace period and does not suspend" do
    ResendMailer.stub(:subscription_notice, { "id" => "email_1" }) do
      handle(event("invoice.payment_failed", invoice("subscription_cycle")),
             stripe_sub(id: "sub_pro", status: "past_due", lookup_key: "draxuvo_pro_monthly"))
    end

    subscription = subscriptions(:pro_co).reload
    assert subscription.past_due?
    assert subscription.active_access?
    assert_in_delta Time.current.to_f, subscription.past_due_since.to_f, 5
    assert_not_nil subscription.past_due_notice_sent_at
  end

  test "paying the pending invoice reactivates a suspended company" do
    ResendMailer.stub(:subscription_notice, { "id" => "email_1" }) do
      handle(event("invoice.payment_failed", invoice("subscription_update")),
             stripe_sub(id: "sub_pro", status: "past_due", lookup_key: "draxuvo_enterprise_monthly"))
    end
    assert subscriptions(:pro_co).reload.suspended?

    handle(event("invoice.paid", invoice("subscription_update")),
           stripe_sub(id: "sub_pro", status: "active", lookup_key: "draxuvo_enterprise_monthly"))

    subscription = subscriptions(:pro_co).reload
    assert subscription.active?
    assert subscription.enterprise?
    assert_nil subscription.suspended_at
    assert_equal "reactivated", subscription.subscription_changes.last.kind
  end
end
