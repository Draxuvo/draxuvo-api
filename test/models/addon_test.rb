require "test_helper"

class AddonTest < ActiveSupport::TestCase
  test "catalog has the pos add-on at 199 pesos a month" do
    pos = Addon.find(:pos)
    assert_equal :pos, pos.key
    assert_equal 19_900, pos.monthly_amount_cents
    assert_equal [ :inventory ], pos.requires
  end

  test "annual price is ten months" do
    assert_equal 199_000, Addon.find(:pos).annual_amount_cents
    assert_equal 19_900, Addon.find(:pos).amount_cents(:monthly)
    assert_equal 199_000, Addon.find("pos").amount_cents("annual")
  end

  test "unknown cycle raises" do
    assert_raises(ArgumentError) { Addon.find(:pos).amount_cents(:weekly) }
    assert_raises(ArgumentError) { Addon.find(:pos).lookup_key(:weekly) }
  end

  test "lookup_key follows the stripe naming" do
    assert_equal "draxuvo_addon_pos_monthly", Addon.find(:pos).lookup_key(:monthly)
    assert_equal "draxuvo_addon_pos_annual", Addon.find(:pos).lookup_key("annual")
  end

  test "parse_lookup_key reads known add-ons and ignores the rest" do
    assert_equal [ :pos, :monthly ], Addon.parse_lookup_key("draxuvo_addon_pos_monthly")
    assert_equal [ :pos, :annual ], Addon.parse_lookup_key("draxuvo_addon_pos_annual")
    assert_nil Addon.parse_lookup_key("draxuvo_addon_unknown_monthly")
    assert_nil Addon.parse_lookup_key("draxuvo_basic_monthly")
    assert_nil Addon.parse_lookup_key(nil)
  end

  test "key? and find accept strings and symbols" do
    assert Addon.key?("pos")
    assert Addon.key?(:pos)
    assert_not Addon.key?("inventory")
    assert_raises(KeyError) { Addon.find(:nope) }
  end

  test "add-on keys are not plan modules" do
    assert_empty Addon::KEYS & Plan::PLAN_MODULES
  end
end
