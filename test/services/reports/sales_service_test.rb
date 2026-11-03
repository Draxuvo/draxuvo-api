require "test_helper"

class Reports::SalesServiceTest < ActiveSupport::TestCase
  RANGE = 1.day.ago..1.day.from_now

  setup do
    @company = companies(:pos_co)
    @ana = users(:pos_staff)
    @luis = users(:pos_staff2)
  end

  def sell(user, *lines, received: 1000)
    charge_cash(open_sale(user, *lines), user, received: received).sale
  end

  def report(range = RANGE) = Reports::SalesService.new(@company, range).call

  test "an empty period reports zeros" do
    result = report
    assert_equal 0.0, result[:total_revenue]
    assert_equal 0, result[:total_sales]
    assert_equal 0, result[:units]
    assert_empty result[:by_product]
    assert_empty result[:by_cashier]
    assert_equal RANGE.first, result[:period][:from]
  end

  test "totals count revenue, sales and units of paid sales" do
    sell(@ana, [ products(:pos_cuaderno), 2 ], [ products(:pos_pluma), 1 ])
    sell(@luis, [ products(:pos_cuaderno), 1 ])

    result = report
    assert_equal 136.5, result[:total_revenue]
    assert_equal 2, result[:total_sales]
    assert_equal 4, result[:units]
  end

  test "by product adds units and revenue per product, best revenue first" do
    sell(@ana, [ products(:pos_cuaderno), 2 ], [ products(:pos_pluma), 1 ])
    sell(@luis, [ products(:pos_cuaderno), 1 ])

    rows = report[:by_product]
    assert_equal [ "Cuaderno profesional", "Pluma azul" ], rows.map { |r| r[:name] }
    assert_equal({ units: 3, revenue: 127.5, sku: "PAP-001" }, rows.first.slice(:units, :revenue, :sku))
    assert_equal products(:pos_cuaderno).id, rows.first[:product_id]
  end

  test "fractional units are reported as decimals" do
    sell(@ana, [ products(:pos_liston), "1.5" ], [ products(:pos_liston), "1" ])
    assert_equal 2.5, report[:by_product].first[:units]
    assert_equal 2.5, report[:units]
  end

  test "cancelled sales do not count anywhere" do
    sale = sell(@ana, [ products(:pos_cuaderno), 2 ])
    sell(@luis, [ products(:pos_pluma), 1 ])
    Sales::Cancel.call(sale, users(:pos_admin), "Error")

    result = report
    assert_equal 9.0, result[:total_revenue]
    assert_equal 1, result[:total_sales]
    assert_equal [ "Pluma azul" ], result[:by_product].map { |r| r[:name] }
  end

  test "open sales do not count" do
    open_sale(@ana, [ products(:pos_cuaderno), 3 ])
    assert_equal 0, report[:total_sales]
  end

  test "the period filters by the day it was paid" do
    sale = sell(@ana, [ products(:pos_cuaderno), 1 ])
    sale.update_columns(paid_at: 10.days.ago)

    assert_equal 0, report[:total_sales]
    assert_equal 1, report(15.days.ago..5.days.ago)[:total_sales]
  end

  test "by cashier groups sales and revenue by who charged them" do
    sell(@ana, [ products(:pos_cuaderno), 2 ])
    sell(@ana, [ products(:pos_pluma), 1 ])
    sell(@luis, [ products(:pos_cuaderno), 1 ])

    rows = report[:by_cashier]
    assert_equal [ @ana.id, @luis.id ], rows.map { |r| r[:user_id] }
    assert_equal({ sales: 2, revenue: 94.0, name: @ana.full_name }, rows.first.slice(:sales, :revenue, :name))
  end

  test "products deleted later still appear by their name at sale time" do
    sell(@ana, [ products(:pos_cuaderno), 1 ])
    SaleItem.update_all(product_id: nil)

    row = report[:by_product].sole
    assert_nil row[:product_id]
    assert_equal "Cuaderno profesional", row[:name]
  end

  test "another company's sales never show up" do
    sell(@ana, [ products(:pos_cuaderno), 1 ])
    other = Reports::SalesService.new(companies(:one), RANGE).call
    assert_equal 0, other[:total_sales]
  end
end
