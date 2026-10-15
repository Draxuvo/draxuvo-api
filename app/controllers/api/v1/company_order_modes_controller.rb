# app/controllers/api/v1/company_order_modes_controller.rb
# Modo de órdenes de la empresa activa (007): service | order. Solo el owner lo cambia.
module Api
  module V1
    class CompanyOrderModesController < BaseController
      before_action :require_owner!

      # PATCH /api/v1/company/order_mode { order_mode: "order" | "service" }
      def update
        mode = params[:order_mode].to_s
        unless Company.order_modes.key?(mode)
          raise ApiErrors::UnprocessableEntityError.new(
            message: I18n.t("company.invalid_order_mode"),
            details: { code: "invalid_order_mode" }
          )
        end

        current_company.update!(order_mode: mode)
        render json: current_company
      end
    end
  end
end
