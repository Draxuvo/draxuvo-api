# app/controllers/api/v1/attendances_controller.rb
module Api
  module V1
    class AttendancesController < BaseController
      requires_module :attendance

      # Filtros inválidos se ignoran (contracts/api.md): type fuera del enum, employee_id vacío
      # o fechas que no se pueden leer no aplican filtro.
      def index
        attendances = current_company.attendances
                                     .includes(:employee)
                                     .search(params[:search])

        attendances = attendances.where(employee_id: params[:employee_id]) if params[:employee_id].present?
        attendances = attendances.where(attendance_type: params[:type])    if Attendance.attendance_types.key?(params[:type])

        from = parse_day(params[:from])
        to   = parse_day(params[:to])
        attendances = attendances.where(checkin_at: from.beginning_of_day..) if from
        attendances = attendances.where(checkin_at: ..to.end_of_day)         if to

        attendances = apply_sort(attendances, allowed: %i[checkin_at checkout_at created_at], default: :checkin_at, default_dir: :desc)
        @pagy, @attendances = pagy(attendances)
        render json: paginate_response(@pagy, @attendances.map { |a| AttendanceSerializer.new(a).as_json })
      end

      private

      # Fecha YYYY-MM-DD interpretada como día completo en Time.zone; nil si no se puede leer.
      def parse_day(value)
        return if value.blank?

        Time.zone.parse(value.to_s)
      rescue ArgumentError
        nil
      end
    end
  end
end
