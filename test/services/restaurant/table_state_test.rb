require "test_helper"

class Restaurant::TableStateTest < ActiveSupport::TestCase
  test "without a check the table is free" do
    assert_equal "free", Restaurant::TableState.call(nil)
    assert_equal "free", Restaurant::TableState.call(checks(:closed_check))
  end

  test "an open check with items in the kitchen is occupied" do
    assert_equal "occupied", Restaurant::TableState.call(checks(:open_check))
  end

  test "an open check with nothing sent yet is occupied" do
    assert_equal "occupied", Restaurant::TableState.call(checks(:takeout_check))
  end

  test "an open check with everything delivered and a balance is to pay" do
    check = settle_check(checks(:open_check))

    assert_equal "to_pay", Restaurant::TableState.call(check)
  end

  test "a check that is fully paid is not to pay" do
    check = settle_check(checks(:open_check))
    check.stub :balance, 0 do
      assert_equal "occupied", Restaurant::TableState.call(check)
    end
  end

  test "uses the counts it is given instead of querying" do
    check = checks(:open_check)

    assert_equal "to_pay", Restaurant::TableState.call(check, counts: { "delivered" => 2 })
    assert_equal "occupied", Restaurant::TableState.call(check, counts: { "delivered" => 1, "ready" => 1 })
  end
end
