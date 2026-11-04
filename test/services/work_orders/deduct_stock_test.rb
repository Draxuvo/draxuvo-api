require "test_helper"

# Spec 054 (H-49): cobrar una orden de trabajo descuenta del inventario lo vendido, sin pasar de cero.
class WorkOrders::DeductStockTest < ActiveSupport::TestCase
  setup do
    @cuaderno = products(:pos_cuaderno) # 18 en existencia
    @pluma = products(:pos_pluma)       # 3 en existencia
  end

  test "charging discounts what was sold and leaves a movement tied to the order" do
    order = done_order([ @cuaderno, 4 ])
    charge_order(order)

    assert_equal 14, @cuaderno.reload.stock
    movement = StockMovement.find_by!(work_order: order)
    assert movement.exit?
    assert_equal 4, movement.qty
    assert_equal users(:pos_admin), movement.user
    assert_equal "Orden ##{order.id}", movement.note
    assert_nil movement.sale_id
    assert_equal 4, order.work_order_items.first.reload.stock_taken
  end

  test "never goes below zero and reports what was missing" do
    order = done_order([ @pluma, 5 ])
    transition = charge_order(order)

    assert_equal 0, @pluma.reload.stock
    assert_equal [ { product_id: @pluma.id, name: @pluma.name, missing: 2 } ], transition.shortages.map { |s| s.merge(missing: s[:missing].to_i) }
    assert_equal 3, order.work_order_items.first.reload.stock_taken
    assert_equal 3, StockMovement.find_by!(work_order: order).qty
    assert order.reload.paid?, "el cobro no se bloquea por falta de existencias"
  end

  test "adds up lines of the same product and shares what was taken in order" do
    order = done_order([ @pluma, 2 ], [ @pluma, 2 ])
    transition = charge_order(order)

    assert_equal 0, @pluma.reload.stock
    assert_equal [ 2, 1 ], order.work_order_items.order(:position).pluck(:stock_taken).map(&:to_i)
    assert_equal 1, transition.shortages.sole[:missing].to_i
    assert_equal 1, StockMovement.where(work_order: order).count
  end

  test "free concepts and products that are not counted do not move stock" do
    service = products(:pos_copia) # servicio: no se cuenta
    before = StockMovement.count
    order = done_order([ service, 3 ], free: 80)
    transition = charge_order(order)

    assert_equal before, StockMovement.count
    assert_empty transition.shortages
    assert_equal [ 0, 0 ], order.work_order_items.order(:position).pluck(:stock_taken).map(&:to_i)
  end

  test "a product that sold out before charging is reported entirely missing without a movement" do
    @pluma.update_columns(stock: 0)
    order = done_order([ @pluma, 2 ])
    transition = charge_order(order)

    assert_equal 2, transition.shortages.sole[:missing].to_i
    assert_empty StockMovement.where(work_order: order)
  end

  test "charging twice does not discount twice" do
    order = done_order([ @cuaderno, 4 ])
    charge_order(order)
    assert_raises(ApiErrors::UnprocessableEntityError) { charge_order(order) }

    assert_equal 14, @cuaderno.reload.stock
    assert_equal 1, StockMovement.where(work_order: order).count
  end

  test "a failed charge discounts nothing" do
    order = done_order([ @cuaderno, 4 ])
    assert_raises(ApiErrors::UnprocessableEntityError) do
      WorkOrders::Transition.call(order, :charge, stock_context, payments: [ { method: "card", amount: 1 } ])
    end

    assert_equal 18, @cuaderno.reload.stock
    assert_empty StockMovement.where(work_order: order)
  end
end
