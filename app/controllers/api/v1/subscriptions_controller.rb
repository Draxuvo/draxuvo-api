# Contrato: specs/002-rebrand-suscripciones/contracts/api.md (/subscription).
# Sin check_subscription!: una empresa con la prueba vencida debe poder ver y pagar su plan.
# Una sucursal (spec 004, R17) ve la suscripción de su principal con managed_by_parent y no cobra:
# checkout, portal, PATCH y DELETE responden 422 billing_managed_by_parent.
module Api
  module V1
    class SubscriptionsController < BaseController
      skip_before_action :check_subscription!

      before_action :require_admin!
      before_action :reject_branch_billing!, except: :show

      # GET /api/v1/subscription
      def show
        render json: serialize(subscription!)
      end

      # PATCH /api/v1/subscription — cambio de plan solo durante la prueba (FR-028) y solo por el super admin
      # (spec 031, FR-001): el dueño y el administrador reciben 403 trial_plan_locked.
      def update
        subscription = subscription!
        plan = valid_plan!(params[:plan])

        unless subscription.trialing?
          raise ApiErrors::UnprocessableEntityError.new(
            message: I18n.t("errors.subscription.not_trialing"),
            details: { code: "not_trialing" }
          )
        end

        unless current_user.super_admin?
          raise ApiErrors::ForbiddenError.new(
            message: I18n.t("errors.subscription.trial_plan_locked"),
            details: { code: "trial_plan_locked" }
          )
        end

        from_plan = subscription.plan
        subscription.update!(plan: plan)
        subscription.log_change!("trial_plan_changed", actor: current_user, from_plan: from_plan, to_plan: plan) if from_plan != plan
        render json: serialize(subscription)
      end

      # POST /api/v1/subscription/checkout
      def checkout
        result = Subscriptions::CreateCheckoutService.new(
          company: current_company,
          plan: required_param!(:plan),
          actor: current_user,
          billing_cycle: params[:billing_cycle],
          success_url: required_param!(:success_url),
          cancel_url: required_param!(:cancel_url)
        ).call

        render json: result, status: :ok
      end

      # POST /api/v1/subscription/portal
      def portal
        result = Subscriptions::PortalService.new(
          company: current_company,
          return_url: required_param!(:return_url)
        ).call

        render json: result, status: :ok
      end

      # DELETE /api/v1/subscription — programa la cancelación al fin del periodo.
      def destroy
        subscription = current_company.subscription
        unless subscription&.active? && subscription.stripe_subscription_id.present?
          raise ApiErrors::NotFoundError
        end

        Subscriptions::CancelService.new(subscription, immediate: false).call
        render json: serialize(subscription.reload)
      end

      private

      def reject_branch_billing!
        return unless current_company.branch?

        raise ApiErrors::UnprocessableEntityError.new(
          message: I18n.t("errors.subscription.billing_managed_by_parent"),
          details: { code: "billing_managed_by_parent" }
        )
      end

      def subscription!
        current_company.billing_subscription || raise(ApiErrors::NotFoundError)
      end

      def serialize(subscription)
        SubscriptionSerializer.new(subscription, company: current_company).as_json
      end

      def required_param!(key)
        value = params[key]
        return value if value.present?

        raise ApiErrors::BadRequestError.new(details: { missing: key.to_s })
      end

      def valid_plan!(value)
        Plan.find(value.to_s).key.to_s
      rescue KeyError
        raise ApiErrors::BadRequestError.new(details: I18n.t("errors.subscription.invalid_plan"))
      end
    end
  end
end
