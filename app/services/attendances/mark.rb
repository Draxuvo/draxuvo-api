# app/services/attendances/mark.rb
# Marca de entrada y salida del propio empleado (spec 026). La hora la pone el servidor.
module Attendances
  class Mark
    class NoOpenAttendance < StandardError; end

    Result = Struct.new(:created, keyword_init: true)

    def initialize(employee)
      @employee = employee
    end

    # { state: "none"|"working"|"done", current:, last: }
    def state
      current = open_scope.order(checkin_at: :desc).first
      last = @employee.attendances.where.not(checkout_at: nil).where(checkin_at: today_range).order(checkout_at: :desc).first
      state = if current then "working" elsif last then "done" else "none" end
      { state: state, current: current, last: last }
    end

    # Idempotente: con un turno de hoy abierto no crea otro. Devuelve true si creó.
    def check_in
      created = false
      @employee.with_lock do
        unless open_scope.exists?
          @employee.attendances.create!(company: @employee.company, checkin_at: Time.current, attendance_type: :normal)
          created = true
        end
      end
      created
    end

    # Cierra el turno abierto de hoy.
    def check_out
      @employee.with_lock do
        attendance = open_scope.order(checkin_at: :desc).first
        raise NoOpenAttendance if attendance.nil?

        attendance.update!(checkout_at: [ Time.current, attendance.checkin_at ].max)
      end
    end

    private

    # Solo cuentan los turnos de hoy: las entradas sin salida de días anteriores (todo el historial anterior a esta
    # función quedó así) no son un turno en curso ni impiden marcar la de hoy.
    def open_scope
      @employee.attendances.where(checkout_at: nil, checkin_at: today_range)
    end

    def today_range
      Time.zone.today.all_day
    end
  end
end
