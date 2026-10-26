module Subscriptions
  # Abre una sesión del Customer Portal de Stripe (research R10). Los cambios vuelven por webhook.
  class PortalService
    def initialize(company:, return_url:)
      @company    = company
      @return_url = return_url
    end

    def call
      Demo::Guard.restrict!(:payment)
      if @company.stripe_id.blank?
        raise ApiErrors::UnprocessableEntityError.new(
          details: { code: "no_billing_account", message: I18n.t("errors.subscription.no_billing_account") }
        )
      end

      params = { customer: @company.stripe_id, return_url: @return_url }
      params[:configuration] = trial_configuration if @company.subscription&.trialing?
      session = Stripe::BillingPortal::Session.create(params)

      { portal_url: session.url }
    end

    private

    # En prueba el portal no puede ofrecer cambio de plan (spec 031): usa una configuración sin él; sin ella, falla cerrado.
    def trial_configuration
      ENV["STRIPE_PORTAL_TRIAL_CONFIGURATION"].presence || raise(
        ApiErrors::UnprocessableEntityError.new(
          message: I18n.t("errors.subscription.portal_unavailable_in_trial"), details: { code: "portal_unavailable_in_trial" }
        )
      )
    end
  end
end
