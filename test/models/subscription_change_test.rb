require "test_helper"

class SubscriptionChangeTest < ActiveSupport::TestCase
  test "accepts the add-on kinds of spec 050" do
    subscription = subscriptions(:pos_co)
    %w[addon_added addon_removed addon_reactivated].each do |kind|
      change = subscription.log_change!(kind, reason: "pos")
      assert change.persisted?, kind
    end
  end

  test "rejects unknown kinds" do
    assert_raises(ActiveRecord::RecordInvalid) { subscriptions(:pos_co).log_change!("nope") }
  end
end
