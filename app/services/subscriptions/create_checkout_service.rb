module Subscriptions
  # Crea una sesión de Stripe Checkout para el plan y ciclo elegidos (contracts/api.md, checkout).
  # No cambia la suscripción: el estado solo se actualiza por webhook (FR-007).
  class CreateCheckoutService
    def initialize(company:, plan:, success_url:, cancel_url:, billing_cycle: nil, actor: nil)
      @actor         = actor
      @company       = company
      @plan          = plan.to_s
      @billing_cycle = billing_cycle.presence&.to_s || "monthly"
      @success_url   = success_url
      @cancel_url    = cancel_url
    end

    def call
      Demo::Guard.restrict!(:payment)
      ensure_not_suspended!
      ensure_no_paid_subscription!
      price_id    = PriceLookupService.price_id(@plan, @billing_cycle)
      tax_rate_id = TaxRateLookupService.tax_rate_id
      ensure_trial_plan_unchanged!
      customer_id = find_or_create_stripe_customer

      session = Stripe::Checkout::Session.create(
        customer: customer_id,
        client_reference_id: @company.id.to_s,
        mode: "subscription",
        line_items: [ { price: price_id, quantity: 1 } ],
        success_url: @success_url,
        cancel_url: @cancel_url,
        metadata: { company_id: @company.id, plan: @plan, billing_cycle: @billing_cycle },
        subscription_data: subscription_data(tax_rate_id),
        tax_id_collection: { enabled: true },
        # Stripe exige que el cliente existente acepte el nombre y la dirección fiscal capturados en el checkout.
        customer_update: { name: "auto", address: "auto" },
        automatic_tax: { enabled: false }
      )

      { checkout_url: session.url }
    end

    private

    # Suspendida (spec 031): se paga la factura pendiente; no se abre otro cobro.
    def ensure_not_suspended!
      return unless @company.subscription&.suspended?

      raise ApiErrors::UnprocessableEntityError.new(
        message: I18n.t("errors.subscription.suspended"), details: { code: "subscription_suspended" }
      )
    end

    # En la prueba solo el super admin cambia el plan; el dueño puede pagar el que ya tiene asignado (spec 031).
    def ensure_trial_plan_unchanged!
      subscription = @company.subscription
      return unless subscription&.trialing?
      return if @actor&.super_admin? || subscription.plan == @plan

      raise ApiErrors::ForbiddenError.new(
        message: I18n.t("errors.subscription.trial_plan_locked"), details: { code: "trial_plan_locked" }
      )
    end

    # El IVA (spec 042) se fija como tasa predeterminada de la suscripción: las renovaciones y los cambios
    # de plan la heredan, y la factura lo desglosa aparte del precio, que va sin IVA.
    def subscription_data(tax_rate_id)
      { default_tax_rates: [ tax_rate_id ] }.merge(trial_options)
    end

    # Pagar durante la prueba respeta los días que sobran: el primer cobro llega al terminar la prueba.
    # Stripe exige que trial_end esté al menos 48 h adelante; con menos, cobra al momento.
    def trial_options
      subscription = @company.subscription
      ends_at = subscription&.trialing? ? subscription.trial_ends_at : nil
      return {} unless ends_at && ends_at > 2.days.from_now + 1.minute

      { trial_end: ends_at.to_i }
    end

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
