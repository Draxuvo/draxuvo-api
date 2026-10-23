# Ayudantes de las pruebas de nómina (spec 037).
module PayrollHelpers
  # Deja en la empresa solo estos empleados activos: [{ name:, salary: }].
  def payroll_employees(company, *specs)
    company.employees.update_all(status: Employee.statuses[:inactive])
    specs.map { |spec| company.employees.create!(status: :active, **spec) }
  end

  def build_payroll_run(company, user, type: :biweekly, starts_on: Date.new(2026, 10, 1), ends_on: Date.new(2026, 10, 15))
    Payroll::BuildRun.call(company: company, user: user, period_type: type, starts_on: starts_on, ends_on: ends_on)
  end

  def approved_payroll_run(company, user, **options)
    run = build_payroll_run(company, user, **options)
    Payroll::Approve.call(run: run, user: user, lock_version: run.lock_version)
  end
end

ActiveSupport::TestCase.include PayrollHelpers
