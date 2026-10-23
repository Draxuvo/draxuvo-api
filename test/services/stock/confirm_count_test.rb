require "test_helper"

class Stock::ConfirmCountTest < ActiveSupport::TestCase
  setup do
    @company = companies(:resto_co)
    @user = users(:resto_waiter)
    @tacos = products(:resto_tacos)
    @cola = products(:resto_cola)
    @count = @company.stock_counts.create!(user: @user)
  end

  def count!(product, qty)
    @count.items.create!(product: product, counted_qty: qty, baseline_stock: product.stock)
  end

  def confirm = Stock::ConfirmCount.call(count: @count, user: users(:resto_owner))

  test "adjusts only the products whose count differs and leaves the rest untouched" do
    count!(@tacos, @tacos.stock + 4)
    count!(@cola, @cola.stock)
    untouched = products(:resto_agua)
    untouched_stock = untouched.stock

    result = confirm

    assert_equal @tacos.stock + 4, @tacos.reload.stock
    assert_equal 1, result.adjustments.size
    adjustment = result.adjustments.first
    assert_equal [ "adjustment", 4, I18n.t("stock.count.note", id: @count.id), users(:resto_owner).id ],
                 [ adjustment.movement_type, adjustment.qty.to_i, adjustment.note, adjustment.user_id ]
    assert_equal untouched_stock, untouched.reload.stock
    assert @count.reload.confirmed?
    assert_equal users(:resto_owner), @count.confirmed_by
  end

  test "computes against the current stock when it changed while counting and says which changed" do
    count!(@cola, 10)
    baseline = @cola.stock
    StockMovement.create!(product: @cola, company: @company, movement_type: :entry, qty: 3, note: "mientras contaban")

    result = confirm

    assert_equal 10, @cola.reload.stock
    assert_equal [ 10 - (baseline + 3) ], result.adjustments.map { |m| m.qty.to_i }
    assert_equal [ @cola.id ], result.changed_since_baseline
  end

  test "counting zero sets the stock to zero for that product only" do
    count!(@tacos, 0)
    confirm

    assert_equal 0, @tacos.reload.stock
  end

  test "confirming again answers the same result without duplicating adjustments" do
    count!(@tacos, @tacos.stock + 2)
    first = confirm

    assert_no_difference -> { StockMovement.count } do
      second = confirm
      assert_equal first.adjustments.map(&:id), second.adjustments.map(&:id)
    end
    assert_equal @tacos.stock + 2, @tacos.reload.stock
  end

  test "a discarded count cannot be confirmed" do
    @count.discarded!

    error = assert_raises(Stock::ConfirmCount::Invalid) { confirm }
    assert_equal :count_closed, error.code
  end

  test "an empty count confirms without adjustments" do
    result = confirm

    assert_empty result.adjustments
    assert @count.reload.confirmed?
  end
end
