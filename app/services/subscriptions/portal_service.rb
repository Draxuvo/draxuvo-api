module Subscriptions
  # Abre una sesión del Customer Portal de Stripe (research R10). Los cambios vuelven por webhook.
  class PortalService
    def initialize(company:, return_url:)
      @company    = company
      @return_url = return_url
    end

    def call
      if @company.stripe_id.blank?
        raise ApiErrors::UnprocessableEntityError.new(
          details: { code: "no_billing_account", message: I18n.t("errors.subscription.no_billing_account") }
        )
      end

      session = Stripe::BillingPortal::Session.create(customer: @company.stripe_id, return_url: @return_url)

      { portal_url: session.url }
    end
  end
end
