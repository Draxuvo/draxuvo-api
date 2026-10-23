require "test_helper"

# Spec 037, plan: crear y aprobar una corrida de 200 empleados en menos de 3 s.
class Payroll::PerformanceTest < ActiveSupport::TestCase
  test "builds and approves a run of 200 employees quickly" do
    company = companies(:pro_co)
    owner = users(:pro_co_owner)
    payroll_employees(company, *Array.new(200) { |i| { name: "Empleado #{i}", salary: 10_000 + i } })

    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    run = build_payroll_run(company, owner, type: :monthly, starts_on: Date.new(2026, 10, 1), ends_on: Date.new(2026, 10, 31))
    Payroll::Approve.call(run: run, user: owner, lock_version: run.lock_version)
    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started

    assert_equal 200, run.payments.count
    assert_operator elapsed, :<, 3.0
  end
end
