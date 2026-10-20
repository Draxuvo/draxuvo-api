# app/controllers/api/v1/company_modules_controller.rb
# Módulos activos de la empresa (FR-027). Se guardan los desactivados; activos = plan - desactivados.
# Solo el super admin los cambia (spec 017), con `X-Company-Id` de la empresa que administra.
module Api
  module V1
    class CompanyModulesController < BaseController
      before_action :require_super_admin!

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

        record_changes(disabled)
        render json: modules_json
      end

      private

      # Guarda la lista y un registro por cada módulo cuyo estado cambió, en una sola transacción (FR-009).
      def record_changes(disabled)
        previous = Array(current_company.disabled_modules).map(&:to_s)
        Company.transaction do
          current_company.update!(disabled_modules: disabled)
          ((previous - disabled).map { |key| [ key, true ] } + (disabled - previous).map { |key| [ key, false ] }).each do |key, enabled|
            current_company.module_changes.create!(actor: current_user, module: key, enabled: enabled)
          end
        end
      end

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
