# app/services/attendances/mark.rb
# Marca de entrada y salida de un empleado. La marca propia (sin `at`) usa la hora del servidor y es idempotente
# (spec 026). Quien marca a otro (spec 036) puede dar `at` (nunca futura) y `strict: true` para que un turno ya
# abierto, una salida sin entrada, una salida anterior a su entrada o un traslape se rechacen con error.
module Attendances
  class Mark
    class NoOpenAttendance < StandardError; end
    class AlreadyOpen < StandardError; end
    class FutureTime < StandardError; end
    class BeforeCheckin < StandardError; end
    class Overlap < StandardError; end

    # Tolerancia de reloj entre cliente y servidor, y umbral para llamar "capturada" a una hora.
    TOLERANCE = 60.seconds
    # Una entrada sin salida de hace más de esto ya no se toma como turno en curso al capturar horas.
    OPEN_WINDOW = 24.hours

    def initialize(employee, actor: nil)
      @employee = employee
      @actor = actor
    end

    # { state: "none"|"working"|"done", current:, last: }
    def state
      current = open_scope.order(checkin_at: :desc).first
      last = @employee.attendances.where.not(checkout_at: nil).where(checkin_at: today_range).order(checkout_at: :desc).first
      state = if current then "working" elsif last then "done" else "none" end
      { state: state, current: current, last: last }
    end

    # Con turno de hoy abierto no crea otro (marca propia) o falla (strict). Devuelve true si creó.
    def check_in(at: nil, strict: false)
      time = resolve_time(at)
      created = false
      @employee.with_lock do
        if open_scope.exists?
          raise AlreadyOpen if strict
        else
          raise Overlap if strict && overlap?(time, nil)

          @employee.attendances.create!(
            company: @employee.company, checkin_at: time, attendance_type: :normal,
            checkin_by: @actor, checkin_captured: captured?(time)
          )
          created = true
        end
      end
      created
    end

    # Cierra el turno abierto: el de hoy (marca propia) o el último sin salida de las últimas 24 h si hay `at`.
    def check_out(at: nil, strict: false)
      time = resolve_time(at)
      @employee.with_lock do
        attendance = at ? recent_open_scope.order(checkin_at: :desc).first : open_scope.order(checkin_at: :desc).first
        raise NoOpenAttendance if attendance.nil?
        raise BeforeCheckin if strict && time < attendance.checkin_at
        raise Overlap if strict && overlap?(attendance.checkin_at, time, except: attendance)

        attendance.update!(
          checkout_at: [ time, attendance.checkin_at ].max, checkout_by: @actor,
          checkout_captured: captured?(time), checkout_recorded_at: Time.current
        )
        attendance
      end
    end

    private

    def resolve_time(at)
      return Time.current if at.blank?

      time = at.respond_to?(:in_time_zone) ? at.in_time_zone : Time.zone.parse(at.to_s)
      raise ArgumentError, "invalid time" if time.nil?
      raise FutureTime if time > Time.current + TOLERANCE

      time
    end

    def captured?(time) = (Time.current - time).abs > TOLERANCE

    # Solo cuentan los turnos de hoy: las entradas sin salida de días anteriores (todo el historial anterior a esta
    # función quedó así) no son un turno en curso ni impiden marcar la de hoy.
    def open_scope
      @employee.attendances.where(checkout_at: nil, checkin_at: today_range)
    end

    def recent_open_scope
      @employee.attendances.where(checkout_at: nil).where(checkin_at: (Time.current - OPEN_WINDOW)..)
    end

    # Un turno de hoy sin salida llega hasta ahora; uno anterior sin salida cuenta solo como su instante de entrada.
    def overlap?(from, to, except: nil)
      scope = @employee.attendances
      scope = scope.where.not(id: except.id) if except
      scope.where("attendances.checkin_at < :to", to: to || Time.current)
           .where("COALESCE(attendances.checkout_at, CASE WHEN attendances.checkin_at >= :day THEN :far ELSE attendances.checkin_at END) > :from",
                  day: Time.zone.today.beginning_of_day, far: 100.years.from_now, from: from)
           .exists?
    end

    def today_range
      Time.zone.today.all_day
    end
  end
end
