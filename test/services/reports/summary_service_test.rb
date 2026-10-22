require "test_helper"

class Reports::SummaryServiceTest < ActiveSupport::TestCase
  RANGE = Time.utc(2026, 3, 1).beginning_of_day..Time.utc(2026, 3, 31).end_of_day

  setup do
    @company = Company.create!(name: "Reportes Resumen")
    @owner = create_member(@company, role: :owner)
    @employee = Employee.create!(company: @company, name: "Ana Activa", salary: 10_000, status: :active)
    @product = Product.create!(company: @company, sku: "R-1", name: "Cable", unit_cost: 10, stock: 0)
  end

  def summary(range = RANGE, period = "month")
    Reports::SummaryService.new(@company, range, period).call
  end

  def order(status: :open, total: 0, created_at: Time.utc(2026, 3, 10), **extra)
    WorkOrder.create!(company: @company, created_by: @owner, title: "Orden", status: status, total: total,
                      created_at: created_at, cancel_reason: (status == :cancelled ? "Razón" : nil), **extra)
  end

  def ticket(order, status:, total:, **attrs)
    Ticket.create!(work_order: order, company: @company, total: total, status: status, **attrs)
  end

  test "has the sections of the plan and echoes the period" do
    result = summary
    assert_equal %i[period income work_orders expenses attendance inventory], result.keys
    assert_equal({ type: "month", from: RANGE.first, to: RANGE.last }, result[:period])
  end

  test "without compare there is no previous block" do
    assert_not summary.key?(:previous)
  end

  test "compare adds income and expenses of the previous range of the same length" do
    ticket(order, status: :paid, total: 300, payment_method: :cash, amount_received: 300, charged_by: @owner,
                  paid_at: Time.utc(2026, 3, 12))
    ticket(order, status: :paid, total: 200, payment_method: :cash, amount_received: 200, charged_by: @owner,
                  paid_at: Time.utc(2026, 2, 5))
    ticket(order, status: :pending, total: 70, created_at: Time.utc(2026, 2, 6))
    StockMovement.create!(company: @company, product: @product, movement_type: :entry, qty: 5, created_at: Time.utc(2026, 2, 7))

    result = Reports::SummaryService.new(@company, RANGE, "custom", compare: true).call
    previous = result[:previous]

    assert_equal 300.0, result[:income][:total_revenue]
    assert_equal 200.0, previous[:income][:total_revenue]
    assert_equal 70.0, previous[:income][:pending_revenue]
    assert_equal 50.0, previous[:expenses][:inventory_cost]
    assert_equal 10_000.0, previous[:expenses][:payroll]
    assert_equal %i[period income expenses], previous.keys
  end

  test "compare with nothing in the previous range reports zeros" do
    previous = Reports::SummaryService.new(@company, RANGE, "custom", compare: true).call[:previous]

    assert_equal 0.0, previous[:income][:total_revenue]
    assert_equal 0.0, previous[:expenses][:inventory_cost]
  end

  test "income separates paid by paid_at from pending by created_at" do
    ticket(order, status: :paid, total: 300, payment_method: :cash, amount_received: 300, charged_by: @owner,
                  paid_at: Time.utc(2026, 3, 12))
    ticket(order, status: :paid, total: 111, payment_method: :cash, amount_received: 111, charged_by: @owner,
                  paid_at: Time.utc(2026, 5, 12))
    ticket(order, status: :pending, total: 80, created_at: Time.utc(2026, 3, 15))
    ticket(order, status: :pending, total: 40, created_at: Time.utc(2026, 1, 15))
    ticket(order, status: :voided, total: 500, payment_method: :cash, amount_received: 500, charged_by: @owner,
                  paid_at: Time.utc(2026, 3, 12), voided_at: Time.current, voided_by: @owner, void_reason: "x",
                  created_at: Time.utc(2026, 3, 15))
    assert_equal({ total_revenue: 300.0, tickets_paid: 1, pending_revenue: 80.0, tickets_pending: 1 }, summary[:income])
  end

  test "work orders are counted by status within the range" do
    order(status: :open, total: 100)
    order(status: :in_progress, total: 200)
    order(status: :done, total: 300)
    order(status: :cancelled)
    order(status: :open, total: 999, created_at: Time.utc(2025, 1, 1))
    result = summary[:work_orders]
    assert_equal 4, result[:total]
    assert_equal 600.0, result[:total_billed]
    assert_equal({ open: 1, in_progress: 1, done: 1, paid: 0, cancelled: 1 }, result[:by_status])
  end

  test "expenses add the active payroll and the cost of entry movements in the range" do
    Employee.create!(company: @company, name: "Baja Inactiva", salary: 5_000, status: :inactive)
    StockMovement.create!(product: @product, company: @company, movement_type: :entry, qty: 5,
                          created_at: Time.utc(2026, 3, 5))
    StockMovement.create!(product: @product, company: @company, movement_type: :exit, qty: 2,
                          created_at: Time.utc(2026, 3, 6))
    StockMovement.create!(product: @product, company: @company, movement_type: :entry, qty: 100,
                          created_at: Time.utc(2025, 1, 6))
    assert_equal({ payroll: 10_000.0, inventory_cost: 50.0, total: 10_050.0 }, summary[:expenses])
  end

  test "attendance counts records by type within the range" do
    Attendance.create!(employee: @employee, company: @company, checkin_at: Time.utc(2026, 3, 2, 8), attendance_type: :normal)
    Attendance.create!(employee: @employee, company: @company, checkin_at: Time.utc(2026, 3, 3, 9), attendance_type: :late)
    Attendance.create!(employee: @employee, company: @company, checkin_at: Time.utc(2026, 3, 4, 8), attendance_type: :absent)
    Attendance.create!(employee: @employee, company: @company, checkin_at: Time.utc(2026, 4, 4, 8), attendance_type: :normal)
    assert_equal({ total: 3, normal: 1, late: 1, absent: 1 }, summary[:attendance])
  end

  test "an empty company reports zeros apart from the payroll" do
    result = Reports::SummaryService.new(Company.create!(name: "Vacía"), RANGE, "week").call
    assert_equal 0.0, result[:income][:total_revenue]
    assert_equal 0, result[:work_orders][:total]
    assert_equal({ payroll: 0.0, inventory_cost: 0.0, total: 0.0 }, result[:expenses])
    assert_equal({ total: 0, normal: 0, late: 0, absent: 0 }, result[:attendance])
  end

  test "basic plan omits income and work orders and keeps expenses, attendance and inventory" do
    @company.subscription.update!(plan: :basic)

    result = Reports::SummaryService.new(@company, RANGE, "month", compare: true).call

    assert_equal %i[period expenses attendance inventory previous], result.keys
    assert_equal %i[period expenses], result[:previous].keys
    assert_equal 10_000.0, result[:expenses][:payroll]
  end

  test "a module taken away by the super admin removes its block" do
    @company.update!(disabled_modules: %w[inventory])

    result = summary

    assert_not result.key?(:inventory)
    assert_equal 0.0, result[:expenses][:inventory_cost]
  end

  test "inventory block reports today's value and low stock" do
    type = ProductType.find_by!(company: @company, counted: true)
    Product.create!(company: @company, sku: "R-2", name: "Tornillo", unit_cost: 2, stock: 10, min_stock: 10, product_type: type)

    assert_equal({ value: 20.0, counted_products: 1, low_stock: 1 }, summary[:inventory])
  end
end
