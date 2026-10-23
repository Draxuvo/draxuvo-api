module Payroll
  # Construye las líneas de una corrida a partir de los empleados activos (spec 037, FR-004 a FR-006).
  # La asistencia es informativa: solo cuenta si el módulo `attendance` está activo.
  class Lines
    def initialize(run)
      @run = run
      @company = run.company
    end

    # Entran los empleados activos con salario capturado: quien no tiene salario (el dueño, por ejemplo) no se paga por
    # aquí y no estorba la aprobación.
    def add_missing!
      taken = @run.payments.pluck(:employee_id)
      employees = @company.employees.active.where("employees.salary > 0").where.not(id: taken).order(:name).to_a
      stats = attendance_stats(employees.map(&:id))
      employees.each { |employee| build(employee, stats[employee.id]) }
      employees.size
    end

    private

    def build(employee, stat)
      monthly = Period.salary_to_cents(employee.salary)
      days = @run.period_days
      @run.payments.create!(
        company: @company, employee: employee, employee_name: employee.name, monthly_salary_cents: monthly,
        period_days: days, days_paid: days,
        salary_cents: Period.line_salary_cents(monthly, @run.period_type, days, days),
        net_cents: Period.line_salary_cents(monthly, @run.period_type, days, days),
        days_attended: stat ? stat[:days] : 0, hours_worked: stat ? stat[:hours] : 0
      )
    end

    # Días distintos con entrada (sin faltas) y horas cerradas por empleado en el rango del periodo.
    def attendance_stats(employee_ids)
      return {} unless @company.module_active?(:attendance) && employee_ids.any?

      range = @run.starts_on.in_time_zone.beginning_of_day..@run.ends_on.in_time_zone.end_of_day
      rows = @company.attendances.where(employee_id: employee_ids, checkin_at: range)
                     .where.not(attendance_type: :absent).pluck(:employee_id, :checkin_at, :checkout_at)
      rows.group_by(&:first).transform_values do |list|
        hours = list.sum { |(_, from, to)| to ? (to - from) / 3600.0 : 0 }
        { days: list.map { |(_, from, _)| from.in_time_zone.to_date }.uniq.size, hours: hours.round(2) }
      end
    end
  end
end
