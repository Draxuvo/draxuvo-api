require "test_helper"

class Subscriptions::SyncServiceTest < ActiveSupport::TestCase
  def stripe_sub(**attrs)
    Stripe::Subscription.construct_from(stripe_sub_hash(**attrs))
  end

  def sync(stripe_sub, subscription: nil, id: nil)
    retrieved = []
    result = Stripe::Subscription.stub(:retrieve, ->(arg, *) { retrieved << arg; stripe_sub }) do
      Subscriptions::SyncService.new(stripe_subscription: id || stripe_sub, subscription: subscription).call
    end
    [ result, retrieved ]
  end

  test "maps each Stripe status to the local one" do
    {
      "trialing" => :trialing, "active" => :active, "past_due" => :past_due,
      "unpaid" => :past_due, "canceled" => :cancelled, "incomplete_expired" => :cancelled
    }.each do |stripe_status, local|
      subscription = subscriptions(:pro_co)
      sync(stripe_sub(id: "sub_pro", status: stripe_status, lookup_key: "draxuvo_pro_monthly"))
      assert_equal local.to_s, subscription.reload.status, "#{stripe_status} debería ser #{local}"
    end
  end

  test "incomplete and unknown statuses keep the previous status" do
    %w[incomplete paused otro].each do |stripe_status|
      sync(stripe_sub(id: "sub_pro", status: stripe_status, lookup_key: "draxuvo_pro_monthly"))
      assert subscriptions(:pro_co).reload.active?, "#{stripe_status} no debería cambiar el estado"
    end
  end

  test "copies plan, cycle, amount and lookup key from the price" do
    subscription = subscriptions(:pro_co)
    sync(stripe_sub(id: "sub_pro", status: "active", lookup_key: "draxuvo_enterprise_annual"))
    subscription.reload
    assert subscription.enterprise?
    assert subscription.annual?
    assert_equal Plan.find(:enterprise).amount_cents(:annual), subscription.amount_cents
    assert_equal "draxuvo_enterprise_annual", subscription.stripe_price_lookup_key
  end

  test "an unknown lookup key leaves plan, cycle and amount alone" do
    subscription = subscriptions(:pro_co)
    sync(stripe_sub(id: "sub_pro", status: "active", lookup_key: "otro_precio"))
    subscription.reload
    assert subscription.pro?
    assert_equal 79_900, subscription.amount_cents
  end

  test "copies the period and cancel_at_period_end" do
    start_at = 3.days.ago.change(usec: 0)
    end_at = 27.days.from_now.change(usec: 0)
    sync(stripe_sub(id: "sub_pro", status: "active", lookup_key: "draxuvo_pro_monthly",
                    cancel_at_period_end: true, period_start: start_at, period_end: end_at))
    subscription = subscriptions(:pro_co).reload
    assert subscription.cancel_at_period_end
    assert_equal start_at, subscription.current_period_start
    assert_equal end_at, subscription.current_period_end
  end

  test "an active subscription clears the trial and the cancellation date" do
    subscription = subscriptions(:one)
    subscription.update!(stripe_subscription_id: "sub_trial", cancelled_at: 1.day.ago)
    sync(stripe_sub(id: "sub_trial", status: "active", lookup_key: "draxuvo_pro_monthly"))
    subscription.reload
    assert subscription.active?
    assert_nil subscription.trial_ends_at
    assert_nil subscription.cancelled_at
  end

  test "a cancelled subscription gets a cancellation date and keeps an existing one" do
    subscription = subscriptions(:pro_co)
    sync(stripe_sub(id: "sub_pro", status: "canceled", lookup_key: "draxuvo_pro_monthly"))
    first = subscription.reload.cancelled_at
    assert_not_nil first
    sync(stripe_sub(id: "sub_pro", status: "canceled", lookup_key: "draxuvo_pro_monthly"))
    assert_equal first, subscription.reload.cancelled_at
  end

  test "uses the given local subscription and stores the Stripe id" do
    subscription = subscriptions(:one)
    result, = sync(stripe_sub(id: "sub_new", status: "active", lookup_key: "draxuvo_basic_monthly"),
                   subscription: subscription)
    assert_equal subscription, result
    assert_equal "sub_new", subscription.reload.stripe_subscription_id
    assert subscription.basic?
  end

  test "accepts a plain id and always re-reads the subscription from Stripe" do
    _, retrieved = sync(stripe_sub(id: "sub_pro", status: "active", lookup_key: "draxuvo_pro_monthly"), id: "sub_pro")
    assert_equal "sub_pro", retrieved.first[:id]
    assert_equal [ "items.data.price" ], retrieved.first[:expand]
  end

  test "does nothing when there is no local subscription" do
    result, = sync(stripe_sub(id: "sub_desconocida", status: "active", lookup_key: "draxuvo_pro_monthly"))
    assert_nil result
  end

  test "does nothing without a Stripe id" do
    Stripe::Subscription.stub(:retrieve, ->(*) { flunk "should not call Stripe" }) do
      assert_nil Subscriptions::SyncService.new(stripe_subscription: "").call
      assert_nil Subscriptions::SyncService.new(stripe_subscription: nil).call
    end
  end

  # --- spec 031 ---

  test "a suspended subscription stays suspended while Stripe still says past_due" do
    subscription = subscriptions(:pro_co)
    subscription.update!(status: :suspended, suspended_at: Time.current, suspension_reason: "plan_change")

    sync(stripe_sub(id: "sub_pro", status: "past_due", lookup_key: "draxuvo_pro_monthly"))

    assert subscription.reload.suspended?
  end

  test "a suspended subscription is reactivated when Stripe says active" do
    subscription = subscriptions(:pro_co)
    subscription.update!(status: :suspended, suspended_at: Time.current, suspension_reason: "plan_change",
                         pending_invoice_url: "https://invoice.test/1")

    sync(stripe_sub(id: "sub_pro", status: "active", lookup_key: "draxuvo_pro_monthly"))

    subscription.reload
    assert subscription.active?
    assert_nil subscription.suspended_at
    assert_nil subscription.pending_invoice_url
    assert_equal "reactivated", subscription.subscription_changes.last.kind
  end

  test "a suspended subscription cancelled in Stripe becomes cancelled" do
    subscription = subscriptions(:pro_co)
    subscription.update!(status: :suspended, suspended_at: Time.current, suspension_reason: "payment_overdue")

    sync(stripe_sub(id: "sub_pro", status: "canceled", lookup_key: "draxuvo_pro_monthly"))

    assert subscription.reload.cancelled?
  end

  test "past_due_since is set on the first past_due, kept on the next syncs and cleared when it is paid" do
    subscription = subscriptions(:pro_co)

    sync(stripe_sub(id: "sub_pro", status: "past_due", lookup_key: "draxuvo_pro_monthly"))
    first = subscription.reload.past_due_since
    assert_not_nil first

    travel 2.days do
      sync(stripe_sub(id: "sub_pro", status: "past_due", lookup_key: "draxuvo_pro_monthly"))
    end
    assert_equal first.to_i, subscription.reload.past_due_since.to_i

    sync(stripe_sub(id: "sub_pro", status: "active", lookup_key: "draxuvo_pro_monthly"))
    assert_nil subscription.reload.past_due_since
  end

  # --- módulos extra (spec 050) ---

  test "a subscription with an add-on item reads the plan from the plan item and saves the add-on" do
    subscription = subscriptions(:basic_co)
    sync(stripe_sub(id: "sub_basic", status: "active", lookup_key: "draxuvo_basic_monthly", extra_lookup_keys: [ "draxuvo_addon_pos_monthly" ]))
    subscription.reload

    assert subscription.basic?
    assert_equal 39_900, subscription.amount_cents
    assert_equal "draxuvo_basic_monthly", subscription.stripe_price_lookup_key
    addon = subscription.addons.sole
    assert_equal "pos", addon.module
    assert_equal "si_draxuvo_addon_pos_monthly", addon.stripe_item_id
    assert_equal 19_900, addon.amount_cents
    assert_nil addon.ends_at
    assert companies(:basic_co).reload.module_active?(:pos)
  end

  test "the plan is found even when the add-on item comes first" do
    subscription = subscriptions(:basic_co)
    hash = stripe_sub_hash(id: "sub_basic", status: "active", lookup_key: "draxuvo_basic_annual", extra_lookup_keys: [ "draxuvo_addon_pos_annual" ])
    hash[:items][:data].reverse!
    sync(Stripe::Subscription.construct_from(hash))
    subscription.reload

    assert subscription.basic?
    assert subscription.annual?
    assert_equal 399_000, subscription.amount_cents
    assert_equal 199_000, subscription.addons.sole.amount_cents
  end

  test "syncing twice does not duplicate the add-on and keeps when it started" do
    subscription = subscriptions(:basic_co)
    2.times { sync(stripe_sub(id: "sub_basic", status: "active", lookup_key: "draxuvo_basic_monthly", extra_lookup_keys: [ "draxuvo_addon_pos_monthly" ])) }

    assert_equal 1, subscription.addons.count
    first = subscription.addons.sole.started_at
    sync(stripe_sub(id: "sub_basic", status: "active", lookup_key: "draxuvo_basic_monthly", extra_lookup_keys: [ "draxuvo_addon_pos_monthly" ]))
    assert_equal first, subscription.addons.sole.reload.started_at
  end

  test "an add-on that Stripe no longer has is closed at the end of the period" do
    subscription = subscriptions(:pos_co)
    assert_nil subscription.addons.sole.ends_at
    sync(stripe_sub(id: "sub_pos", status: "active", lookup_key: "draxuvo_basic_monthly", period_end: 12.days.from_now))

    addon = subscription.addons.sole.reload
    assert_in_delta 12.days.from_now.to_f, addon.ends_at.to_f, 5
    assert_nil addon.stripe_item_id
    assert companies(:pos_co).reload.module_active?(:pos)
  end

  test "an add-on with a pending end is not touched by the sync" do
    subscription = subscriptions(:pos_co)
    ends_at = 5.days.from_now.change(usec: 0)
    subscription.addons.update_all(ends_at: ends_at)
    sync(stripe_sub(id: "sub_pos", status: "active", lookup_key: "draxuvo_basic_monthly"))

    assert_equal ends_at, subscription.addons.sole.reload.ends_at
  end

  test "an unknown add-on price is ignored" do
    subscription = subscriptions(:basic_co)
    sync(stripe_sub(id: "sub_basic", status: "active", lookup_key: "draxuvo_basic_monthly", extra_lookup_keys: [ "draxuvo_addon_otro_monthly" ]))

    assert_empty subscription.addons.reload
  end

  test "a plan change keeps the add-on contracted (spec 050, FR-005)" do
    subscription = subscriptions(:pos_co)
    sync(stripe_sub(id: "sub_pos", status: "active", lookup_key: "draxuvo_pro_monthly", extra_lookup_keys: [ "draxuvo_addon_pos_monthly" ]))

    subscription.reload
    assert subscription.pro?
    assert_equal 79_900, subscription.amount_cents
    assert_nil subscription.addons.sole.ends_at
    assert companies(:pos_co).reload.module_active?(:pos)
    assert_equal 79_900 + 19_900, subscription.subtotal_cents
  end
end
