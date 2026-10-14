# app/controllers/api/v1/company_modules_controller.rb
# Módulos activos de la empresa actual (FR-027). Se guardan los desactivados; activos = plan - desactivados.
module Api
  module V1
    class CompanyModulesController < BaseController
      before_action :require_admin!

      # PATCH /api/v1/company/modules { disabled_modules: [] }
      def update
        raise ApiErrors::BadRequestError.new(details: "disabled_modules") unless params.key?(:disabled_modules)

        disabled = Array(params[:disabled_modules]).map(&:to_s).uniq
        available = current_company.available_modules.map(&:to_s)

        outside = disabled.find { |key| available.exclude?(key) }
        if outside
          raise ApiErrors::UnprocessableEntityError.new(
            message: I18n.t("errors.module_not_in_plan", module: I18n.t("modules.#{outside}", default: outside)),
            details: { code: "module_not_in_plan", module: outside }
          )
        end

        current_company.update!(disabled_modules: disabled)
        render json: modules_json
      end

      private

      def modules_json
        {
          active_modules: current_company.active_modules,
          available_modules: current_company.available_modules,
          disabled_modules: current_company.disabled_modules
        }
      end
    end
  end
end
