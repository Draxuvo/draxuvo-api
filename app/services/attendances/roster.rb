# app/services/attendances/roster.rb
# Lista del día por empleado (spec 036): todos los empleados activos con su estado y el turno que cuenta ese día.
# Un turno que cruza medianoche cuenta en el día de su entrada. Dos consultas, sin N+1.
module Attendances
  class Roster
    Row = Struct.new(:employee, :state, :attendance, keyword_init: true)

    def self.call(company, date)
      new(company, date).call
    end

    def initialize(company, date)
      @company = company
      @day = date.in_time_zone.all_day
    end

    def call
      employees = @company.employees.team.active.order(:name).to_a
      by_employee = @company.attendances.where(employee_id: employees.map(&:id), checkin_at: @day)
                            .includes(:checkin_by, :checkout_by).order(:checkin_at).group_by(&:employee_id)

      employees.map do |employee|
        shifts = by_employee[employee.id] || []
        # El turno abierto manda; si no, el último cerrado del día.
        attendance = shifts.reverse.find { |a| a.checkout_at.nil? } || shifts.last
        state = if attendance.nil? then "none" elsif attendance.checkout_at.nil? then "working" else "done" end
        Row.new(employee: employee, state: state, attendance: attendance)
      end
    end
  end
end
