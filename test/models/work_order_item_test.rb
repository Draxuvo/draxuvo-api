require "test_helper"

class WorkOrderItemTest < ActiveSupport::TestCase
  test "ya no tiene status ni completed_at" do
    assert_not_includes WorkOrderItem.column_names, "status"
    assert_not_includes WorkOrderItem.column_names, "completed_at"
  end

  test "valida cantidad y precio" do
    item = WorkOrderItem.new(description: "x", quantity: 0, unit_price: -1)
    assert_not item.valid?
    assert item.errors[:quantity].any?
    assert item.errors[:unit_price].any?
  end

  test "subtotal" do
    assert_equal 30, WorkOrderItem.new(unit_price: 10, quantity: 3).subtotal
  end
end
