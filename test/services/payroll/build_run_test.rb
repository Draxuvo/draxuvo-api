require "test_helper"

class Payroll::BuildRunTest < ActiveSupport::TestCase
  setup do
    @company = companies(:pro_co)
    @owner = users(:pro_co_owner)
    @ana, @beto = payroll_employees(@company, { name: "Ana", salary: 12_000 }, { name: "Beto", salary: nil })
  end

  test "creates a draft with one line per active employee" do
    run = build_payroll_run(@company, @owner)

    assert run.draft?
    assert_equal %w[Ana Beto], run.payments.order(:employee_name).pluck(:employee_name)
    ana = run.payments.find_by!(employee: @ana)
    assert_equal [ 1_200_000, 15, 15, 600_000, 600_000 ], [ ana.monthly_salary_cents, ana.period_days, ana.days_paid, ana.salary_cents, ana.net_cents ]
    assert_equal 0, run.payments.find_by!(employee: @beto).net_cents
    assert_equal 600_000, run.total_cents
    assert_equal [ "created" ], run.events.pluck(:action)
  end

  test "skips inactive employees" do
    @beto.update!(status: :inactive)
    assert_equal [ "Ana" ], build_payroll_run(@company, @owner).payments.pluck(:employee_name)
  end

  test "attendance is informational: counts distinct days without absences and closed hours" do
    @company.attendances.create!(employee: @ana, checkin_at: Time.zone.local(2026, 10, 2, 9), checkout_at: Time.zone.local(2026, 10, 2, 17))
    @company.attendances.create!(employee: @ana, checkin_at: Time.zone.local(2026, 10, 3, 9), checkout_at: Time.zone.local(2026, 10, 3, 13))
    @company.attendances.create!(employee: @ana, checkin_at: Time.zone.local(2026, 10, 4, 9), attendance_type: :absent)
    @company.attendances.create!(employee: @ana, checkin_at: Time.zone.local(2026, 10, 20, 9), checkout_at: Time.zone.local(2026, 10, 20, 17))

    line = build_payroll_run(@company, @owner).payments.find_by!(employee: @ana)
    assert_equal [ 2, 12.0 ], [ line.days_attended, line.hours_worked.to_f ]
  end

  test "rejects an overlapping run but allows it once the other is cancelled" do
    @beto.update!(salary: 3_000)
    first = approved_payroll_run(@company, @owner)

    error = assert_raises(Payroll::Error) { build_payroll_run(@company, @owner, starts_on: Date.new(2026, 10, 10), ends_on: Date.new(2026, 10, 20)) }
    assert_equal [ :period_overlap, first.id ], [ error.code, error.details[:run_id] ]

    Payroll::Cancel.call(run: first, user: @owner, reason: "Error")
    assert build_payroll_run(@company, @owner, starts_on: Date.new(2026, 10, 10), ends_on: Date.new(2026, 10, 20)).persisted?
  end

  test "rejects invalid periods" do
    [ [ :weekly, Date.new(2026, 10, 1), Date.new(2026, 10, 9) ],
      [ :biweekly, Date.new(2026, 10, 1), Date.new(2026, 10, 18) ],
      [ :monthly, Date.new(2026, 10, 1), Date.new(2026, 11, 2) ],
      [ :monthly, Date.new(2026, 10, 5), Date.new(2026, 10, 1) ],
      [ :daily, Date.new(2026, 10, 1), Date.new(2026, 10, 1) ] ].each do |type, from, to|
      error = assert_raises(Payroll::Error, "#{type} #{from} #{to}") { build_payroll_run(@company, @owner, type: type, starts_on: from, ends_on: to) }
      assert_equal :period_invalid, error.code
    end
  end

  test "refresh adds new active employees and drops inactive lines without adjustments" do
    run = build_payroll_run(@company, @owner)
    carla = @company.employees.create!(name: "Carla", salary: 6_000, status: :active)
    @beto.update!(status: :inactive)
    old = @company.employees.create!(name: "Vieja", salary: 1_000, status: :active, created_at: 1.day.ago(run.created_at))

    Payroll::RefreshEmployees.call(run: run, user: @owner)

    assert_not run.payments.exists?(employee: old), "una ficha anterior a la corrida no se agrega sola"
    assert_equal %w[Ana Carla], run.payments.order(:employee_name).pluck(:employee_name)
    assert_equal 900_000, run.reload.total_cents
    assert_equal carla.id, run.payments.find_by!(employee_name: "Carla").employee_id
  end
end
