require "test_helper"

# Spec 054 (H-49): anular el cobro de una orden regresa al inventario exactamente lo que salió.
class WorkOrders::RestoreStockTest < ActiveSupport::TestCase
  setup do
    @cuaderno = products(:pos_cuaderno) # 18
    @pluma = products(:pos_pluma)       # 3
  end

  test "voiding returns what was discounted with an entry tied to the order" do
    order = done_order([ @cuaderno, 4 ])
    charge_order(order)
    assert_equal 14, @cuaderno.reload.stock
    void_order(order)

    assert_equal 18, @cuaderno.reload.stock
    entry = StockMovement.find_by!(work_order: order, movement_type: :entry)
    assert_equal 4, entry.qty
    assert_equal "Anulación de cobro de la orden ##{order.id}", entry.note
    assert_equal 0, order.work_order_items.first.reload.stock_taken
  end

  test "returns only what really left when stock fell short" do
    order = done_order([ @pluma, 5 ])
    charge_order(order)
    void_order(order)

    assert_equal 3, @pluma.reload.stock
    assert_equal 3, StockMovement.find_by!(work_order: order, movement_type: :entry).qty
  end

  test "an order charged before the fix returns nothing" do
    order = done_order([ @cuaderno, 4 ])
    charge_order(order)
    order.work_order_items.update_all(stock_taken: 0) # como una orden cobrada antes de la spec
    @cuaderno.update_columns(stock: 18)
    void_order(order)

    assert_equal 18, @cuaderno.reload.stock
    assert_empty StockMovement.where(work_order: order, movement_type: :entry)
  end

  test "voiding twice does not return twice" do
    order = done_order([ @cuaderno, 4 ])
    charge_order(order)
    void_order(order)
    assert_raises(ApiErrors::UnprocessableEntityError) { void_order(order) }

    assert_equal 18, @cuaderno.reload.stock
    assert_equal 1, StockMovement.where(work_order: order, movement_type: :entry).count
  end

  test "charging again after a void discounts again" do
    order = done_order([ @cuaderno, 4 ])
    charge_order(order)
    void_order(order)
    charge_order(order)

    assert_equal 14, @cuaderno.reload.stock
    assert_equal 4, order.work_order_items.first.reload.stock_taken
  end

  test "a deleted or no longer counted product is not touched" do
    order = done_order([ @cuaderno, 4 ])
    charge_order(order)
    @cuaderno.update_columns(tracks_stock: false, stock: 7)
    void_order(order)

    assert_equal 7, @cuaderno.reload.stock
    assert_empty StockMovement.where(work_order: order, movement_type: :entry)
  end
end
