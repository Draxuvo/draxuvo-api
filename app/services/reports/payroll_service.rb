module Reports
  class PayrollService
    def initialize(company, range)
      @company = company
      @range   = range
    end

    def call
      employees = @company.employees.where(status: :active).order(:name)

      {
        period:        { from: @range.first, to: @range.last },
        total_payroll: employees.sum("COALESCE(salary, 0)").to_f,
        headcount:     employees.count,
        runs:          runs_summary,
        employees:     employees.map { |e| employee_data(e) }
      }
    end

    private

    # Spec 037: lo pagado y lo pendiente de las corridas cuyo periodo termina en el rango, una sola base para que
    # pantalla, CSV y reporte cuadren. Las canceladas y los borradores no cuentan.
    def runs_summary
      runs = @company.payroll_runs.where(status: %i[approved partial paid], ends_on: @range.first.to_date..@range.last.to_date)
      payments = @company.payroll_payments.where(payroll_run_id: runs.select(:id))
      {
        count:         runs.count,
        paid_cents:    payments.paid.sum(:net_cents),
        pending_cents: payments.pending.sum(:net_cents)
      }
    end

    def employee_data(employee)
      attendances  = employee.attendances.where(checkin_at: @range)
      type_counts  = attendances.group(:attendance_type).count
      hours_worked = attendances.where.not(checkout_at: nil)
                                .sum("EXTRACT(EPOCH FROM (checkout_at - checkin_at)) / 3600")
                                .to_f

      {
        id:           employee.id,
        name:         employee.name,
        position:     employee.position,
        department:   employee.department,
        salary:       employee.salary.to_f,
        days_present: attendances.count,
        hours_worked: hours_worked.round(2),
        attendance:   {
          normal: type_counts["normal"].to_i,
          late:   type_counts["late"].to_i,
          absent: type_counts["absent"].to_i
        }
      }
    end
  end
end
