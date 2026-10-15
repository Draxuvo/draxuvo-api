require "test_helper"

class Subscriptions::CancelServiceTest < ActiveSupport::TestCase
  test "schedules the cancellation at period end in Stripe and locally" do
    subscription = subscriptions(:pro_co)
    calls = []
    with_cancel_stubs(calls) do
      result = Subscriptions::CancelService.new(subscription).call
      assert_same subscription, result
    end
    assert_equal [ { id: "sub_pro", params: { cancel_at_period_end: true } } ], calls
    assert subscription.reload.cancel_at_period_end
    assert subscription.active?
  end

  test "does nothing without a Stripe subscription" do
    subscription = subscriptions(:one)
    calls = []
    with_cancel_stubs(calls) do
      Subscriptions::CancelService.new(subscription).call
    end
    assert_empty calls
    assert_not subscription.reload.cancel_at_period_end
  end

  test "immediate cancellation cancels in Stripe and marks the subscription cancelled" do
    subscription = subscriptions(:pro_co)
    cancelled = []
    Stripe::Subscription.stub(:cancel, ->(id, *) { cancelled << id }) do
      Subscriptions::CancelService.new(subscription, immediate: true).call
    end
    assert_equal [ "sub_pro" ], cancelled
    subscription.reload
    assert subscription.cancelled?
    assert_not_nil subscription.cancelled_at
    assert_not subscription.cancel_at_period_end
  end

  test "immediate cancellation without a Stripe id skips Stripe" do
    subscription = subscriptions(:one)
    Stripe::Subscription.stub(:cancel, ->(*) { flunk "should not call Stripe" }) do
      Subscriptions::CancelService.new(subscription, immediate: true).call
    end
    assert subscription.reload.cancelled?
  end

  test "a Stripe error leaves the local subscription untouched" do
    subscription = subscriptions(:pro_co)
    Stripe::Subscription.stub(:update, ->(*) { raise Stripe::APIConnectionError, "sin red" }) do
      assert_raises(Stripe::APIConnectionError) { Subscriptions::CancelService.new(subscription).call }
    end
    assert_not subscription.reload.cancel_at_period_end
  end
end
