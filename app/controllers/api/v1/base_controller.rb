# app/controllers/api/v1/base_controller.rb
module Api
  module V1
    class BaseController < ApplicationController
      include Authenticable
      include Authorizable
      include ModuleGate

      rescue_from ApiErrors::BaseError,          with: :handle_api_error
      rescue_from ActiveRecord::RecordNotFound,  with: :handle_not_found
      rescue_from ActiveRecord::RecordInvalid,   with: :handle_invalid
      rescue_from Demo::Restricted,              with: :handle_demo_restricted

      before_action :authenticate_request
      before_action :check_subscription!
      before_action :enter_demo_context

      private

      # Aplica orden a un scope. Solo permite columnas explícitamente declaradas.
      # Uso: apply_sort(scope, allowed: %i[name created_at])
      def apply_sort(scope, allowed:, default: :created_at, default_dir: :asc)
        column    = params[:sort_by]&.to_sym
        column    = allowed.include?(column) ? column : default
        direction = params[:sort_dir]&.downcase == "desc" ? :desc : default_dir
        scope.order(column => direction)
      end

      # Empleado ligado a la persona en la empresa activa (nil si no tiene). Es por empresa: un usuario
      # puede ser dueño de una y staff de otra (spec 007, R5).
      def current_employee
        return @current_employee if defined?(@current_employee)

        @current_employee = current_company.employees.find_by(user_id: current_user.id)
      end

      # Quién actúa, para las reglas de WorkOrders::Transition y allowed_actions.
      def work_order_context
        WorkOrders::Transition::Context.new(user: current_user, role: current_role, employee: current_employee)
      end

      def current_company
        @current_company ||= begin
          company_id = request.headers["X-Company-Id"].presence
          raise ApiErrors::BadRequestError.new(details: I18n.t("auth.no_company")) if company_id.blank?
          scope = current_user.super_admin? ? Company : current_user.companies
          company = scope.find(company_id)
          reject_inactive_employee!(company)
          company
        rescue ActiveRecord::RecordNotFound
          raise ApiErrors::ForbiddenError.new(details: I18n.t("auth.no_company"))
        end
      end

      # Spec 036: dar de baja a un empleado suspende su acceso a esa empresa; reactivarlo lo restablece.
      def reject_inactive_employee!(company)
        return if current_user.super_admin?
        return unless company.employees.inactive.exists?(user_id: current_user.id)

        raise ApiErrors::ForbiddenError.new(
          message: I18n.t("auth.employee_inactive"), details: { code: "employee_inactive" }
        )
      end

      # Rol con el que actúa el usuario en la empresa activa (R16): super_admin o el de su membresía.
      def current_role
        @current_role ||= current_user.role_in(current_company)
      end

      def handle_api_error(error)
        render json: error.as_json, status: error.status
      end

      def handle_not_found
        render json: ApiErrors::NotFoundError.new(details: I18n.t("errors.resource_not_found")).as_json,
               status: :not_found
      end

      # El acceso lo da la suscripción de billing_company (R17). Una sucursal además exige que la
      # principal tenga multi_company en su plan; si no, queda bloqueada sin borrar datos (FR-029).
      def check_subscription!
        return if current_user.super_admin?

        billing = current_company.billing_company
        subscription = billing&.subscription
        subscription = Subscription.start_trial!(current_company, plan: :pro) if subscription.nil? && !current_company.branch?

        raise_subscription_suspended!(subscription) if subscription&.suspended?
        unless subscription&.active_access?
          raise ApiErrors::ForbiddenError.new(details: I18n.t("errors.subscription.inactive"))
        end

        return unless current_company.branch?
        return if billing.available_modules.include?(:multi_company)

        raise_module_not_in_plan!(:multi_company)
      end

      # Suspendida por falta de pago (spec 031): 403 con el motivo; la URL de pago solo para dueño y administrador.
      def raise_subscription_suspended!(subscription)
        details = { code: "subscription_suspended", reason: subscription.suspension_reason, plan: subscription.plan,
                    cancels_at: subscription.cancels_at }
        details[:pay_url] = subscription.pending_invoice_url if %w[owner admin].include?(current_role)
        raise ApiErrors::ForbiddenError.new(message: I18n.t("errors.subscription.suspended"), details: details)
      end

      # Spec 039: si la empresa activa es una demo, lo que sale al exterior (correo, WhatsApp, Stripe) se simula o se
      # bloquea, y una demo vencida o terminada deja de servir aunque su token siga vigente. Se decide por la empresa
      # del encabezado (el visitante es dueño y puede teclear datos de terceros). Va después de check_subscription!,
      # que ya cargó `current_company`: no agrega consultas.
      def enter_demo_context
        return if request.headers["X-Company-Id"].blank?

        Current.demo = current_company.demo?
        return unless Current.demo
        return if current_company.demo_session&.usable?

        raise ApiErrors::ForbiddenError.new(message: I18n.t("demo.errors.demo_expired"), details: { code: "demo_expired" })
      end

      def handle_demo_restricted(error)
        render json: ApiErrors::ForbiddenError.new(
          message: I18n.t("demo.errors.demo_restricted"), details: { code: "demo_restricted", action: error.action }
        ).as_json, status: :forbidden
      end

      def handle_invalid(e)
        render json: ApiErrors::UnprocessableEntityError.new(
          details: e.record.errors.full_messages
        ).as_json, status: :unprocessable_entity
      end
    end
  end
end
