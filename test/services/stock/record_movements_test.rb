require "test_helper"

class Stock::RecordMovementsTest < ActiveSupport::TestCase
  setup do
    @company = companies(:one)
    @user = users(:pro_co_owner)
    @product = products(:one)
  end

  def record(entries) = Stock::RecordMovements.call(company: @company, user: @user, entries: entries)

  test "records entries, exits and adjustments and updates the stock once per product" do
    before = @product.stock
    record([ { product: @product, delta: 10, type: :entry, note: "Compra" },
             { product: @product, delta: -3, type: :exit, note: "Salida" },
             { product: @product, delta: -2, type: :adjustment, note: "Conteo" } ])

    assert_equal before + 5, @product.reload.stock
    moves = @product.stock_movements.order(:id).last(3)
    assert_equal %w[entry exit adjustment], moves.map(&:movement_type)
    assert_equal [ 10, 3, -2 ], moves.map { |m| m.qty.to_i }
    assert(moves.all? { |m| m.user_id == @user.id })
  end

  test "ignores zero deltas" do
    assert_no_difference -> { StockMovement.count } do
      record([ { product: @product, delta: 0, type: :adjustment, note: "x" } ])
    end
  end

  test "an adjustment below zero rejects everything" do
    before = @product.stock
    assert_no_difference -> { StockMovement.count } do
      error = assert_raises(Stock::RecordMovements::Invalid) do
        record([ { product: @product, delta: 5, type: :entry }, { product: @product, delta: -(before + 10), type: :adjustment } ])
      end
      assert_equal :insufficient_stock, error.code
    end
    assert_equal before, @product.reload.stock
  end

  test "rejects fractions in whole-unit types and products that are not counted" do
    error = assert_raises(Stock::RecordMovements::Invalid) { record([ { product: @product, delta: 1.5, type: :entry } ]) }
    assert_equal :integer_only, error.code

    service = @company.products.create!(name: "Servicio", sku: "SRV-1", product_type: product_types(:one_sold))
    error = assert_raises(Stock::RecordMovements::Invalid) { record([ { product: service, delta: 1, type: :entry } ]) }
    assert_equal :not_counted, error.code
  end
end
