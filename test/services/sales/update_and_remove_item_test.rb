require "test_helper"

class Sales::UpdateAndRemoveItemTest < ActiveSupport::TestCase
  setup do
    @sale = open_sale(users(:pos_staff), [ products(:pos_cuaderno), 2 ], [ products(:pos_pluma), 1 ])
    @item = @sale.sale_items.find_by(product: products(:pos_cuaderno))
  end

  test "changes the quantity and recalculates the total" do
    Sales::UpdateItem.call(@sale, @item.id, "5")
    assert_equal 5, @item.reload.quantity
    assert_equal BigDecimal("221.50"), @sale.reload.total
  end

  test "quantity zero removes the item" do
    Sales::UpdateItem.call(@sale, @item.id, "0")
    assert_nil SaleItem.find_by(id: @item.id)
    assert_equal BigDecimal("9.00"), @sale.reload.total
  end

  test "rejects negative, text and fractional quantities for whole products" do
    %w[-1 x 1.5].each do |quantity|
      error = assert_raises(ApiErrors::BaseError) { Sales::UpdateItem.call(@sale, @item.id, quantity) }
      assert_equal "invalid_quantity", error.details[:code]
    end
  end

  test "an item from another sale is not found" do
    other = open_sale(users(:pos_staff2), [ products(:pos_cuaderno), 1 ])
    error = assert_raises(ApiErrors::NotFoundError) { Sales::UpdateItem.call(@sale, other.sale_items.first.id, "3") }
    assert_equal "item_not_found", error.details[:code]
  end

  test "removes an item and recalculates" do
    Sales::RemoveItem.call(@sale, @item.id)
    assert_equal 1, @sale.reload.sale_items.count
    assert_equal BigDecimal("9.00"), @sale.total
    assert_raises(ApiErrors::NotFoundError) { Sales::RemoveItem.call(@sale, @item.id) }
  end

  test "a closed sale cannot be edited" do
    @sale.update!(status: :paid, paid_at: Time.current, charged_by: users(:pos_staff))
    assert_raises(ApiErrors::BaseError) { Sales::UpdateItem.call(@sale, @item.id, "3") }
    assert_raises(ApiErrors::BaseError) { Sales::RemoveItem.call(@sale, @item.id) }
  end
end
