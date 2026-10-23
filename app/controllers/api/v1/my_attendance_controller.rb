# app/controllers/api/v1/my_attendance_controller.rb
module Api
  module V1
    # Asistencia de quien consulta (spec 026): estado de hoy, marcar entrada y marcar salida.
    class MyAttendanceController < BaseController
      requires_module :attendance

      def today
        render json: payload
      end

      def check_in
        return not_eligible unless current_employee

        created = mark.check_in
        render json: payload, status: created ? :created : :ok
      end

      def check_out
        return not_eligible unless current_employee

        mark.check_out
        render json: payload
      rescue Attendances::Mark::NoOpenAttendance
        render json: { error: { status: 422, code: "no_open_attendance", message: I18n.t("attendance.no_open") } },
               status: :unprocessable_entity
      end

      private

      def mark
        @mark ||= Attendances::Mark.new(current_employee, actor: current_user)
      end

      def not_eligible
        render json: { error: { status: 422, code: "not_eligible", message: I18n.t("attendance.not_eligible") } },
               status: :unprocessable_entity
      end

      def payload
        return { eligible: false, state: "none", current: nil, last: nil, server_time: Time.current } unless current_employee

        s = mark.state
        {
          eligible: true,
          state: s[:state],
          current: s[:current] && shape(s[:current]),
          last: s[:last] && shape(s[:last]),
          server_time: Time.current
        }
      end

      def shape(a)
        { id: a.id, checkin_at: a.checkin_at, checkout_at: a.checkout_at,
          open: a.open?, duration_minutes: a.duration_minutes }
      end
    end
  end
end
