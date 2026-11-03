require "test_helper"

class SubscriptionAddonTest < ActiveSupport::TestCase
  setup do
    @subscription = subscriptions(:basic_co)
    @company = companies(:basic_co)
  end

  def build_addon(**attrs)
    SubscriptionAddon.new({ subscription: @subscription, company: @company, module: "pos", amount_cents: 19_900,
                            started_at: Time.current }.merge(attrs))
  end

  test "a valid add-on has no end date and is current" do
    addon = build_addon
    assert addon.valid?
    assert addon.current?
    assert_not addon.ending?
    assert_equal "active", addon.status
  end

  test "the module must be a known add-on" do
    assert_not build_addon(module: "inventory").valid?
    assert_not build_addon(module: "nope").valid?
  end

  test "one row per subscription and module" do
    build_addon.save!
    assert_not build_addon.valid?
  end

  test "amount must be a non-negative integer and started_at is required" do
    assert_not build_addon(amount_cents: -1).valid?
    assert_not build_addon(amount_cents: 1.5).valid?
    assert_not build_addon(started_at: nil).valid?
  end

  test "a future end date keeps it current and marks it ending" do
    addon = build_addon(ends_at: 10.days.from_now).tap(&:save!)
    assert addon.current?
    assert addon.ending?
    assert_equal "ending", addon.status
    assert_includes SubscriptionAddon.current, addon
  end

  test "a past end date makes it not current" do
    addon = build_addon(ends_at: 1.day.ago).tap(&:save!)
    assert_not addon.current?
    assert_not addon.ending?
    assert_not_includes SubscriptionAddon.current, addon
  end

  test "addon returns the catalog entry" do
    assert_equal :pos, build_addon.addon.key
  end

  test "destroying the subscription removes its add-ons" do
    build_addon.save!
    assert_difference -> { SubscriptionAddon.count }, -1 do
      @subscription.destroy
    end
  end
end
