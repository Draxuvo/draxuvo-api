require "test_helper"

class Reports::ExpensesServiceTest < ActiveSupport::TestCase
  RANGE = Time.utc(2025, 1, 1).beginning_of_day..Time.utc(2026, 12, 31).end_of_day

  setup do
    @company = Company.create!(name: "Reportes Gastos")
    @cable = Product.create!(company: @company, sku: "C-1", name: "Cable", unit_cost: 10.5, stock: 0)
    @free = Product.create!(company: @company, sku: "F-1", name: "Regalo", unit_cost: nil, stock: 0)
  end

  def movement(product, type, qty, at, note: nil)
    StockMovement.create!(product: product, company: @company, movement_type: type, qty: qty, created_at: at, note: note)
  end

  def report(group_by = "month", range = RANGE)
    Reports::ExpensesService.new(@company, range, group_by).call
  end

  test "an empty company reports zeros" do
    result = report
    assert_equal 0.0, result[:total_expenses]
    assert_equal 0, result[:payroll][:headcount]
    assert_empty result[:inventory_cost][:movements]
    assert_empty result[:inventory_cost][:by_period]
  end

  test "payroll counts only active employees ordered by name" do
    Employee.create!(company: @company, name: "Zoe", salary: 3_000, status: :active, position: "Cajera")
    Employee.create!(company: @company, name: "Abel", salary: 5_000, status: :active)
    Employee.create!(company: @company, name: "Baja", salary: 9_000, status: :inactive)
    Employee.create!(company: @company, name: "Sin sueldo", salary: nil, status: :active)
    payroll = report[:payroll]
    assert_equal 8_000.0, payroll[:total]
    assert_equal 3, payroll[:headcount]
    assert_equal [ "Abel", "Sin sueldo", "Zoe" ], payroll[:employees].map { |e| e[:name] }
    assert_equal "Cajera", payroll[:employees].last[:position]
    assert_equal 0.0, payroll[:employees][1][:salary]
  end

  test "only entry movements in the range count as inventory expense" do
    movement(@cable, :entry, 10, Time.utc(2026, 2, 1), note: "Compra")
    movement(@cable, :exit, 4, Time.utc(2026, 2, 2))
    movement(@cable, :adjustment, 3, Time.utc(2026, 2, 3))
    movement(@cable, :entry, 50, Time.utc(2024, 2, 1))
    inventory = report[:inventory_cost]
    assert_equal 105.0, inventory[:total]
    assert_equal 1, inventory[:movements].size
    row = inventory[:movements].first
    assert_equal({ product_name: "Cable", sku: "C-1", qty: 10, unit_cost: 10.5, cost: 105.0, note: "Compra" },
                 row.slice(:product_name, :sku, :qty, :unit_cost, :cost, :note))
  end

  test "a product without unit cost adds nothing" do
    movement(@free, :entry, 20, Time.utc(2026, 2, 1))
    assert_equal 0.0, report[:inventory_cost][:total]
    assert_equal 0.0, report[:inventory_cost][:movements].first[:cost]
  end

  test "the total is payroll plus inventory" do
    Employee.create!(company: @company, name: "Ana", salary: 1_000, status: :active)
    movement(@cable, :entry, 2, Time.utc(2026, 2, 1))
    assert_equal 1_021.0, report[:total_expenses]
  end

  test "groups inventory cost by month, week and year" do
    movement(@cable, :entry, 1, Time.utc(2026, 1, 5, 12))
    movement(@cable, :entry, 2, Time.utc(2026, 1, 6, 12))
    movement(@cable, :entry, 4, Time.utc(2026, 1, 12, 12))
    movement(@cable, :entry, 8, Time.utc(2025, 12, 1, 12))
    assert_equal [ [ "2025-12", 84.0, 1 ], [ "2026-01", 73.5, 3 ] ],
                 report[:inventory_cost][:by_period].map { |g| [ g[:period], g[:cost], g[:count] ] }
    assert_equal [ "2026-W02", "2026-W03" ], report("week")[:inventory_cost][:by_period].map { |g| g[:period] }.last(2)
    assert_equal [ "2025", "2026" ], report("year")[:inventory_cost][:by_period].map { |g| g[:period] }
  end

  test "the period echoes the range" do
    assert_equal({ from: RANGE.first, to: RANGE.last }, report[:period])
  end

  test "groups inventory cost by day" do
    movement(@cable, :entry, 2, Time.utc(2026, 3, 10, 18))
    movement(@cable, :entry, 4, Time.utc(2026, 3, 10, 19))
    movement(@cable, :entry, 1, Time.utc(2026, 3, 12, 18))
    groups = report("day")[:inventory_cost][:by_period]

    assert_equal %w[2026-03-10 2026-03-12], groups.map { |g| g[:period] }
    assert_equal [ 63.0, 10.5 ], groups.map { |g| g[:cost] }
  end
end
