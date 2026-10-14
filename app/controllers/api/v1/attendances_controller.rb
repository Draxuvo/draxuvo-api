# app/controllers/api/v1/attendances_controller.rb
module Api
  module V1
    class AttendancesController < BaseController
      requires_module :attendance

      def index
        attendances = current_company.attendances
                                     .includes(:employee)
                                     .search(params[:search])

        attendances = attendances.where(employee_id: params[:employee_id]) if params[:employee_id]
        attendances = attendances.where("checkin_at >= ?", params[:from])  if params[:from]
        attendances = attendances.where("checkin_at <= ?", params[:to])    if params[:to]

        attendances = apply_sort(attendances, allowed: %i[checkin_at checkout_at created_at], default: :checkin_at, default_dir: :desc)
        @pagy, @attendances = pagy(attendances)
        render json: paginate_response(@pagy, @attendances)
      end
    end
  end
end
