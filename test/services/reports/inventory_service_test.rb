require "test_helper"

class Reports::InventoryServiceTest < ActiveSupport::TestCase
  RANGE = Time.utc(2026, 3, 1).beginning_of_day..Time.utc(2026, 3, 31).end_of_day

  setup do
    @company = Company.create!(name: "Reportes Inventario")
    @counted = ProductType.find_by!(company: @company, counted: true)
    @service_type = ProductType.find_by!(company: @company, counted: false)
  end

  def product(sku, type: @counted, **attrs)
    Product.create!({ company: @company, sku: sku, name: "Prod #{sku}", product_type: type, stock: 0 }.merge(attrs))
  end

  def move(product, type, qty, at: Time.utc(2026, 3, 10, 12))
    movement = StockMovement.create!(company: @company, product: product, movement_type: type, qty: qty)
    movement.update_columns(created_at: at)
    movement
  end

  def report(range = RANGE) = Reports::InventoryService.new(@company, range).call

  test "value is stock times unit cost and products without cost are counted apart" do
    product("A", stock: 10, unit_cost: 5)
    product("B", stock: 4)

    stock = report[:stock]

    assert_equal 50.0, stock[:value]
    assert_equal 2, stock[:counted_products]
    assert_equal 1, stock[:without_cost]
  end

  test "types that are not counted never appear" do
    product("S", type: @service_type, stock: 0)
    sold = product("C", stock: 5, unit_cost: 1)
    move(sold, :entry, 5)

    result = report

    assert_equal 1, result[:stock][:counted_products]
    assert_equal [ sold.id ], result[:movements][:rows].map { |r| r[:id] }
  end

  test "low stock uses the same rule as Product.low_stock" do
    low = product("L", stock: 2, min_stock: 5)
    product("OK", stock: 20, min_stock: 5)
    product("NOMIN", stock: 0)

    assert_equal [ low.id ], report[:stock][:low_stock].map { |r| r[:id] }
    assert_equal Product.low_stock.where(company: @company).count, report[:stock][:low_stock].size
  end

  test "movements add entries, exits and signed adjustments inside the period only" do
    item = product("M", stock: 0, unit_cost: 1)
    move(item, :entry, 20)
    move(item, :exit, 6)
    move(item, :adjustment, -2)
    move(item, :entry, 99, at: Time.utc(2026, 4, 5))

    row = report[:movements][:rows].first

    assert_equal [ 20, 6, -2 ], row.values_at(:entries, :exits, :adjustments)
    assert_not report[:movements][:truncated]
  end

  test "stock does not change with the period but movements do" do
    item = product("P", stock: 0, unit_cost: 2)
    move(item, :entry, 10)
    other = Time.utc(2026, 1, 1).beginning_of_day..Time.utc(2026, 1, 31).end_of_day

    assert_equal report[:stock], report(other)[:stock]
    assert_empty report(other)[:movements][:rows]
  end

  test "is scoped to the company" do
    other = Company.create!(name: "Otra")
    Product.create!(company: other, sku: "X", name: "Ajeno", product_type: ProductType.find_by!(company: other, counted: true),
                    stock: 9, unit_cost: 9)

    assert_equal 0, report[:stock][:counted_products]
  end
end
