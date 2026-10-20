require "test_helper"

class Reports::IncomeServiceTest < ActiveSupport::TestCase
  RANGE = Time.utc(2025, 1, 1).beginning_of_day..Time.utc(2026, 12, 31).end_of_day

  setup do
    @company = Company.create!(name: "Reportes Ingresos")
    @owner = create_member(@company, role: :owner)
    @worker = Employee.create!(company: @company, name: "Técnico Uno", status: :active)
  end

  def ticket(total:, status: :paid, paid_at: nil, employee: nil, title: "Orden")
    order = WorkOrder.create!(company: @company, created_by: @owner, title: title, employee: employee, total: total)
    attrs = { work_order: order, company: @company, total: total, status: status }
    attrs.merge!(payment_method: :cash, amount_received: total, charged_by: @owner, paid_at: paid_at) if status == :paid
    # Un ticket anulado se cobró antes: conserva paid_at y su monto, y solo por eso no cuenta como ingreso.
    attrs.merge!(payment_method: :cash, amount_received: total, charged_by: @owner, paid_at: paid_at,
                 voided_at: Time.current, voided_by: @owner, void_reason: "Error") if status == :voided
    Ticket.create!(**attrs)
  end

  def report(group_by = "month", range = RANGE)
    Reports::IncomeService.new(@company, range, group_by).call
  end

  test "an empty period reports zeros" do
    result = report
    assert_equal 0.0, result[:total_revenue]
    assert_equal 0, result[:total_tickets]
    assert_empty result[:by_period]
    assert_empty result[:breakdown]
    assert_equal RANGE.first, result[:period][:from]
    assert_equal RANGE.last, result[:period][:to]
  end

  test "only paid tickets count as revenue" do
    ticket(total: 100, paid_at: Time.utc(2026, 3, 10))
    ticket(total: 250.5, paid_at: Time.utc(2026, 3, 11))
    ticket(total: 900, status: :pending)
    ticket(total: 700, status: :voided, paid_at: Time.utc(2026, 3, 12))
    result = report
    assert_equal 350.5, result[:total_revenue]
    assert_equal 2, result[:total_tickets]
    assert_equal 2, result[:breakdown].size
  end

  test "tickets paid outside the range are excluded" do
    ticket(total: 100, paid_at: Time.utc(2026, 3, 10))
    ticket(total: 500, paid_at: Time.utc(2024, 3, 10))
    assert_equal 100.0, report[:total_revenue]
  end

  test "other companies are not included" do
    other = Company.create!(name: "Otra")
    other_owner = create_member(other, role: :owner)
    order = WorkOrder.create!(company: other, created_by: other_owner, title: "Ajena", total: 999)
    Ticket.create!(work_order: order, company: other, total: 999, status: :paid, payment_method: :cash,
                   amount_received: 999, charged_by: other_owner, paid_at: Time.utc(2026, 3, 10))
    assert_equal 0.0, report[:total_revenue]
  end

  test "groups by month by default" do
    ticket(total: 100, paid_at: Time.utc(2026, 1, 5))
    ticket(total: 50, paid_at: Time.utc(2026, 1, 25))
    ticket(total: 70, paid_at: Time.utc(2026, 2, 3))
    assert_equal [ { period: "2026-01", revenue: 150.0, count: 2 }, { period: "2026-02", revenue: 70.0, count: 1 } ],
                 report[:by_period]
    assert_equal "2026-01", report("anything")[:by_period].first[:period]
  end

  test "groups by week" do
    ticket(total: 100, paid_at: Time.utc(2026, 1, 5, 12))
    ticket(total: 50, paid_at: Time.utc(2026, 1, 6, 12))
    ticket(total: 70, paid_at: Time.utc(2026, 1, 12, 12))
    assert_equal [ { period: "2026-W02", revenue: 150.0, count: 2 }, { period: "2026-W03", revenue: 70.0, count: 1 } ],
                 report("week")[:by_period]
  end

  test "groups by year" do
    ticket(total: 100, paid_at: Time.utc(2025, 6, 5))
    ticket(total: 50, paid_at: Time.utc(2026, 6, 5))
    ticket(total: 25, paid_at: Time.utc(2026, 7, 5))
    assert_equal [ { period: "2025", revenue: 100.0, count: 1 }, { period: "2026", revenue: 75.0, count: 2 } ],
                 report("year")[:by_period]
  end

  test "the breakdown lists each ticket with its order and employee" do
    paid = ticket(total: 120, paid_at: Time.utc(2026, 3, 10), employee: @worker, title: "Instalación")
    ticket(total: 80, paid_at: Time.utc(2026, 3, 11), title: "Sin técnico")
    first, second = report[:breakdown]
    assert_equal paid.id, first[:id]
    assert_equal paid.folio, first[:folio]
    assert_equal 120.0, first[:total]
    assert_equal({ id: paid.work_order_id, title: "Instalación", employee: "Técnico Uno" }, first[:work_order])
    assert_nil second[:work_order][:employee]
  end

  test "the breakdown shows restaurant tickets with their table and waiter instead of a work order" do
    company = companies(:resto_co)
    range = Time.utc(2020, 1, 1)..Time.utc(2030, 12, 31)
    tickets(:resto_paid_ticket).update_columns(paid_at: Time.utc(2026, 3, 10))

    result = Reports::IncomeService.new(company, range, "month").call

    assert_equal 70.0, result[:total_revenue]
    row = result[:breakdown].first
    assert_equal "Mesa 2", row[:work_order][:title]
    assert_equal users(:resto_waiter).full_name, row[:work_order][:employee]
    assert_nil row[:work_order][:id]
  end

  # --- spec 015: desglose por método y por terminal ---

  test "by_method and by_terminal add the active payments of orders and restaurant checks" do
    company = companies(:pro_co)
    range = Time.utc(2020, 1, 1)..Time.utc(2030, 12, 31)
    paid = tickets(:pro_paid_ticket)
    paid.update_columns(paid_at: Time.utc(2026, 3, 10), payment_method: Ticket.payment_methods[:mixed])
    paid.ticket_payments.create!(company: company, payment_method: :cash, amount: 120, amount_received: 200, created_by: users(:pro_co_owner))
    paid.ticket_payments.create!(company: company, payment_method: :card, amount: 80, created_by: users(:pro_co_owner))
    paid.ticket_payments.create!(company: company, payment_method: :card, amount: 999, created_by: users(:pro_co_owner),
                                 voided_at: Time.current)

    result = Reports::IncomeService.new(company, range, "month").call

    assert_equal [ { method: "card", label: "Tarjeta", total: 580.0, count: 2 }, { method: "cash", label: "Efectivo", total: 120.0, count: 1 } ],
                 result[:by_method]
    bbva = payment_terminals(:pro_bbva)
    assert_equal [ { terminal: { id: bbva.id, name: "BBVA caja 1", provider: "bbva" }, total: 500.0, count: 1 },
                   { terminal: nil, total: 80.0, count: 1 } ], result[:by_terminal]
  end

  test "restaurant check payments count with their terminal" do
    company = companies(:resto_co)
    range = Time.utc(2020, 1, 1)..Time.utc(2030, 12, 31)
    tickets(:resto_paid_ticket).update_columns(paid_at: Time.utc(2026, 3, 10))
    CheckPayment.where(check: checks(:closed_check)).update_all(payment_method: CheckPayment.payment_methods[:card],
                                                               terminal_id: payment_terminals(:resto_point).id, reference: "R1")

    result = Reports::IncomeService.new(company, range, "month").call

    assert_equal "card", result[:by_method].first[:method]
    assert_equal "Point barra", result[:by_terminal].first.dig(:terminal, :name)
  end
end
