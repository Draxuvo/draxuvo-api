require "test_helper"

class StripeEventTest < ActiveSupport::TestCase
  def attrs
    { stripe_event_id: "evt_test_1", event_type: "invoice.paid", processed_at: Time.current }
  end

  test "a complete event is valid" do
    assert StripeEvent.new(attrs).valid?
  end

  test "all three fields are required" do
    event = StripeEvent.new
    assert_not event.valid?
    %i[stripe_event_id event_type processed_at].each { |attr| assert event.errors[attr].any? }
  end

  test "stripe_event_id must be unique" do
    StripeEvent.create!(attrs)
    duplicate = StripeEvent.new(attrs)
    assert_not duplicate.valid?
    assert duplicate.errors[:stripe_event_id].any?
  end

  test "the unique index backs the validation" do
    StripeEvent.create!(attrs)
    assert_raises(ActiveRecord::RecordNotUnique) { StripeEvent.new(attrs).save!(validate: false) }
  end
end
