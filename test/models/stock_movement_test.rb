require "test_helper"

class StockMovementTest < ActiveSupport::TestCase
  def movement(type, qty, product: products(:one))
    StockMovement.new(product: product, company: product.company, movement_type: type, qty: qty)
  end

  test "qty is required and cannot be zero" do
    assert_not movement(:entry, nil).valid?
    zero = movement(:entry, 0)
    assert_not zero.valid?
    assert zero.errors[:qty].any?
  end

  test "an entry adds to the stock" do
    assert_difference -> { products(:one).reload.stock }, 7 do
      movement(:entry, 7).save!
    end
  end

  test "an exit subtracts from the stock" do
    assert_difference -> { products(:one).reload.stock }, -4 do
      movement(:exit, 4).save!
    end
  end

  test "entry and exit use the absolute value of qty" do
    assert_difference -> { products(:one).reload.stock }, 3 do
      movement(:entry, -3).save!
    end
    assert_difference -> { products(:one).reload.stock }, -2 do
      movement(:exit, -2).save!
    end
  end

  test "a positive adjustment raises the stock" do
    assert_difference -> { products(:one).reload.stock }, 3 do
      movement(:adjustment, 3).save!
    end
  end

  test "a negative adjustment lowers the stock" do
    assert_difference -> { products(:one).reload.stock }, -2 do
      movement(:adjustment, -2).save!
    end
  end

  test "a negative adjustment cannot leave the stock below zero" do
    adjustment = movement(:adjustment, -999)
    assert_not adjustment.save
    assert adjustment.errors[:qty].any?
    assert_equal 18, products(:one).reload.stock
  end

  test "search matches the product name or the note" do
    assert_includes StockMovement.search("contacto"), stock_movements(:one)
    assert_includes StockMovement.search("merma"), stock_movements(:two_adjustment)
    assert_not_includes StockMovement.search("merma"), stock_movements(:one)
    assert_equal StockMovement.count, StockMovement.search("").count
  end

  test "movement types come from the enum" do
    assert_equal({ "entry" => 0, "exit" => 1, "adjustment" => 2 }, StockMovement.movement_types)
    assert stock_movements(:two_adjustment).adjustment?
  end
end
