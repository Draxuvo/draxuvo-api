module Subscriptions
  # Crea una sesión de Stripe Checkout para el plan y ciclo elegidos (contracts/api.md, checkout).
  # No cambia la suscripción: el estado solo se actualiza por webhook (FR-007).
  class CreateCheckoutService
    def initialize(company:, plan:, success_url:, cancel_url:, billing_cycle: nil)
      @company       = company
      @plan          = plan.to_s
      @billing_cycle = billing_cycle.presence&.to_s || "monthly"
      @success_url   = success_url
      @cancel_url    = cancel_url
    end

    def call
      ensure_no_paid_subscription!
      price_id    = PriceLookupService.price_id(@plan, @billing_cycle)
      customer_id = find_or_create_stripe_customer

      session = Stripe::Checkout::Session.create(
        customer: customer_id,
        client_reference_id: @company.id.to_s,
        mode: "subscription",
        line_items: [ { price: price_id, quantity: 1 } ],
        success_url: @success_url,
        cancel_url: @cancel_url,
        metadata: { company_id: @company.id, plan: @plan, billing_cycle: @billing_cycle },
        tax_id_collection: { enabled: true },
        automatic_tax: { enabled: false }
      )

      { checkout_url: session.url }
    end

    private

    # Una suscripción pagada vigente se administra desde el portal, no con otro checkout.
    def ensure_no_paid_subscription!
      subscription = @company.subscription
      return unless subscription
      return unless subscription.active? || subscription.past_due?
      return if subscription.stripe_subscription_id.blank?

      raise ApiErrors::UnprocessableEntityError.new(
        message: I18n.t("errors.subscription.subscription_already_active"),
        details: { code: "subscription_already_active" }
      )
    end

    def find_or_create_stripe_customer
      return @company.stripe_id if @company.stripe_id.present?

      customer = Stripe::Customer.create(
        name: @company.name,
        metadata: { company_id: @company.id, slug: @company.slug }
      )
      @company.update_column(:stripe_id, customer.id)
      customer.id
    end
  end
end
