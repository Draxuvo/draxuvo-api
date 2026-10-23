require "test_helper"

class Reports::PayrollServiceTest < ActiveSupport::TestCase
  RANGE = Time.utc(2026, 3, 1).beginning_of_day..Time.utc(2026, 3, 31).end_of_day

  setup do
    @company = Company.create!(name: "Reportes Nómina")
    @ana = Employee.create!(company: @company, name: "Ana", position: "Cajera", department: "Tienda", salary: 4_000, status: :active)
  end

  def check_in(employee, from, to = nil, type: :normal)
    Attendance.create!(employee: employee, company: @company, checkin_at: from, checkout_at: to, attendance_type: type)
  end

  def report(range = RANGE)
    Reports::PayrollService.new(@company, range).call
  end

  test "totals the active payroll only" do
    Employee.create!(company: @company, name: "Baja", salary: 7_000, status: :inactive)
    Employee.create!(company: @company, name: "Beto", salary: nil, status: :active)
    result = report
    assert_equal 4_000.0, result[:total_payroll]
    assert_equal 2, result[:headcount]
    assert_equal [ "Ana", "Beto" ], result[:employees].map { |e| e[:name] }
  end

  test "reports each employee profile" do
    data = report[:employees].first
    assert_equal({ id: @ana.id, name: "Ana", position: "Cajera", department: "Tienda", salary: 4_000.0 },
                 data.slice(:id, :name, :position, :department, :salary))
  end

  test "counts days present and hours worked inside the range" do
    check_in(@ana, Time.utc(2026, 3, 2, 8), Time.utc(2026, 3, 2, 16, 30))
    check_in(@ana, Time.utc(2026, 3, 3, 8), Time.utc(2026, 3, 3, 12))
    check_in(@ana, Time.utc(2026, 3, 4, 8), nil)
    check_in(@ana, Time.utc(2026, 4, 4, 8), Time.utc(2026, 4, 4, 18))
    data = report[:employees].first
    assert_equal 3, data[:days_present]
    assert_equal 12.5, data[:hours_worked]
  end

  test "counts attendance by type" do
    check_in(@ana, Time.utc(2026, 3, 2, 8), type: :normal)
    check_in(@ana, Time.utc(2026, 3, 3, 8), type: :late)
    check_in(@ana, Time.utc(2026, 3, 4, 8), type: :late)
    check_in(@ana, Time.utc(2026, 3, 5, 8), type: :absent)
    assert_equal({ normal: 1, late: 2, absent: 1 }, report[:employees].first[:attendance])
  end

  test "an employee without records has zeros" do
    data = report[:employees].first
    assert_equal 0, data[:days_present]
    assert_equal 0.0, data[:hours_worked]
    assert_equal({ normal: 0, late: 0, absent: 0 }, data[:attendance])
  end

  test "other companies' employees are not included" do
    other = Company.create!(name: "Ajena")
    Employee.create!(company: other, name: "Ajeno", salary: 1_000, status: :active)
    assert_equal 1, report[:headcount]
  end

  test "echoes the period" do
    assert_equal({ from: RANGE.first, to: RANGE.last }, report[:period])
  end

  test "runs summary adds paid and pending of the runs ending in the range" do
    owner = User.create!(first_name: "Dueño", last_name: "Nómina", email: "dueno-nomina@test.dev", phone: "5512340000", password: "password123", active: true)
    run = Payroll::BuildRun.call(company: @company, user: owner, period_type: :biweekly,
                                 starts_on: Date.new(2026, 3, 16), ends_on: Date.new(2026, 3, 31))
    run = Payroll::Approve.call(run: run, user: owner, lock_version: run.lock_version)
    # Pagada ya en abril: el reporte de marzo la cuenta por el periodo, no por la fecha de pago.
    Payroll::Pay.call(run: run, user: owner, payment_method: "cash", paid_on: Time.zone.today)
    Payroll::BuildRun.call(company: @company, user: owner, period_type: :biweekly, starts_on: Date.new(2026, 3, 1), ends_on: Date.new(2026, 3, 15))

    assert_equal({ count: 1, paid_cents: 200_000, pending_cents: 0 }, report[:runs])
    assert_equal({ count: 0, paid_cents: 0, pending_cents: 0 }, report(Time.utc(2026, 5, 1).beginning_of_day..Time.utc(2026, 5, 31).end_of_day)[:runs])
  end
end
