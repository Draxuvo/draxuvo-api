# Módulos extra de la suscripción (spec 050, contracts/api.md): contratar, dar de baja y reactivar. Solo dueño y
# administrador; una sucursal no cobra (lo hace su principal); una demo no tiene pagos. Como Suscripción, no pasa por
# `check_subscription!`: se administra aunque la prueba haya vencido (el servicio pide una suscripción pagada).
module Api
  module V1
    class SubscriptionAddonsController < BaseController
      skip_before_action :check_subscription!

      before_action :require_admin!
      before_action :reject_branch_billing!

      # POST /api/v1/subscription/addons — { module: "pos" }
      def create
        service.add(required_module)
        render json: serialize, status: :created
      end

      # DELETE /api/v1/subscription/addons/:module
      def destroy
        service.remove(params[:module])
        render json: serialize
      end

      # POST /api/v1/subscription/addons/:module/reactivate
      def reactivate
        service.reactivate(params[:module])
        render json: serialize
      end

      private

      def service = Subscriptions::AddonService.new(company: current_company, actor: current_user)

      def serialize
        subscription = current_company.billing_subscription.reload
        SubscriptionSerializer.new(subscription, company: current_company).as_json
      end

      def required_module
        params[:module].presence || raise(ApiErrors::BadRequestError.new(details: { missing: "module" }))
      end

      def reject_branch_billing!
        return unless current_company.branch?

        raise ApiErrors::UnprocessableEntityError.new(
          message: I18n.t("errors.subscription.billing_managed_by_parent"), details: { code: "billing_managed_by_parent" }
        )
      end
    end
  end
end
