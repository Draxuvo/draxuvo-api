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
    assert_equal 70_000, subscription.amount_cents
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
end
