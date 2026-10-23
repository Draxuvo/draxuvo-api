module Payroll
  # Recalcula salario, bonos, deducciones y neto de una línea y el total de su corrida (spec 037, FR-008).
  # Solo en borrador: con la corrida aprobada los montos están congelados.
  class Recalculate
    def self.payment!(payment)
      run = payment.payroll_run
      salary = Period.line_salary_cents(payment.monthly_salary_cents, run.period_type, payment.days_paid, payment.period_days)
      sums = payment.adjustments.group(:kind).sum(:amount_cents)
      bonus = sums.fetch("bonus", 0)
      deduction = sums.fetch("deduction", 0)
      payment.update!(salary_cents: salary, bonus_cents: bonus, deduction_cents: deduction,
                      net_cents: salary + bonus - deduction)
      run!(run)
    end

    # Total de la corrida; sube lock_version para que quien la tenía abierta (aprobar, editar) vea el conflicto.
    def self.run!(run)
      total = run.payments.sum(:net_cents)
      PayrollRun.where(id: run.id).update_all([ "total_cents = ?, lock_version = lock_version + 1", total ])
      run.reload
    end
  end
end
