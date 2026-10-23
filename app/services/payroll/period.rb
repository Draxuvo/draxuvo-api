module Payroll
  # Aritmética de periodos (spec 037, R3 y R4). El salario del empleado es mensual; todo en centavos enteros y
  # redondeo half-up una sola vez por paso.
  module Period
    MAX_DAYS = { weekly: 7, biweekly: 16, monthly: 31 }.freeze
    FRACTION = { weekly: Rational(12, 52), biweekly: Rational(1, 2), monthly: Rational(1) }.freeze

    module_function

    # Días naturales del rango, ambos extremos incluidos.
    def days(starts_on, ends_on) = (ends_on - starts_on).to_i + 1

    def period_salary_cents(monthly_cents, type)
      (Rational(monthly_cents.to_i) * FRACTION.fetch(type.to_sym)).round
    end

    def line_salary_cents(monthly_cents, type, days_paid, period_days)
      (Rational(period_salary_cents(monthly_cents, type) * days_paid.to_i, period_days)).round
    end

    # employees.salary es decimal en pesos; la nómina trabaja en centavos.
    def salary_to_cents(salary) = (salary.to_d * 100).round.to_i
  end
end
