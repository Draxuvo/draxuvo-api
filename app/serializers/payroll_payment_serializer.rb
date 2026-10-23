# Línea de una corrida de nómina (spec 037). `method` es el método de pago (la columna es payment_method).
class PayrollPaymentSerializer
  def initialize(payment, adjustments: true, receipt: false)
    @payment = payment
    @adjustments = adjustments
    @receipt = receipt
  end

  def as_json(*)
    p = @payment
    json = {
      id: p.id, payroll_run_id: p.payroll_run_id, employee_id: p.employee_id, employee_name: p.employee_name,
      monthly_salary_cents: p.monthly_salary_cents, period_days: p.period_days, days_paid: p.days_paid,
      salary_cents: p.salary_cents, bonus_cents: p.bonus_cents, deduction_cents: p.deduction_cents,
      net_cents: p.net_cents, days_attended: p.days_attended, hours_worked: p.hours_worked.to_f, status: p.status,
      method: p.payment_method, reference: p.reference, paid_on: p.paid_on,
      paid_by: p.paid_by && { id: p.paid_by.id, name: p.paid_by.full_name }
    }
    json[:adjustments] = p.adjustments.sort_by(&:id).map { |a| PayrollAdjustmentSerializer.new(a).as_json } if @adjustments
    if @receipt
      run = p.payroll_run
      json[:run] = { id: run.id, period_type: run.period_type, starts_on: run.starts_on, ends_on: run.ends_on }
      json[:company] = { name: p.company.name }
    end
    json
  end
end
