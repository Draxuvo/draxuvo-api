# app/controllers/api/v1/company_modules_controller.rb
# Módulos activos de la empresa (FR-027). Se guardan los desactivados; activos = plan - desactivados.
# Solo el super admin los cambia (spec 017), con `X-Company-Id` de la empresa que administra.
module Api
  module V1
    class CompanyModulesController < BaseController
      before_action :require_super_admin!

      # GET /api/v1/company/modules (spec 053): estado de los módulos y de los extras, y los últimos cambios.
      def show
        render json: modules_json.merge(addons: addons_json, changes: changes_json)
      end

      # PATCH /api/v1/company/modules { disabled_modules: [] }
      def update
        raise ApiErrors::BadRequestError.new(details: "disabled_modules") unless params.key?(:disabled_modules)

        # Spec 053: un extra se enciende y apaga con su propia ruta, no con `disabled_modules`.
        disabled = Array(params[:disabled_modules]).map(&:to_s).uniq - Addon::KEYS.map(&:to_s)
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

      def addons_json
        subscription = current_company.billing_subscription
        cycle = subscription&.billing_cycle || "monthly"
        Addon.all.map do |addon|
          row = subscription&.addons&.find_by(module: addon.key.to_s)
          {
            key: addon.key.to_s,
            requires: addon.requires.map(&:to_s),
            available: addon.available?,
            price: Plan::CYCLES.index_with { |c| addon.amount_cents(c) },
            cycle: cycle.to_s,
            state: addon_state(row, subscription),
            ends_at: row&.ends_at
          }
        end
      end

      # off, trial (encendido sin cobro en la prueba), active o ending (baja programada).
      def addon_state(row, subscription)
        return "off" unless row&.current?
        return "ending" if row.ending?

        subscription&.trialing? && row.stripe_item_id.blank? ? "trial" : "active"
      end

      def changes_json
        current_company.module_changes.includes(:actor).order(created_at: :desc).limit(10).map do |change|
          { module: change.module, enabled: change.enabled, actor: change.actor.full_name, amount_before_cents: change.amount_before_cents,
            amount_after_cents: change.amount_after_cents, created_at: change.created_at }
        end
      end

      def modules_json
        {
          active_modules: current_company.active_modules,
          available_modules: current_company.available_modules,
          disabled_modules: current_company.disabled_modules,
          module_sources: current_company.module_sources
        }
      end
    end
  end
end
