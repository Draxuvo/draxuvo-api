module Subscriptions
  # Procesa un evento de Stripe ya verificado (research R11, contracts/api.md).
  # Cada evento se registra en StripeEvent: un duplicado no hace nada. Los eventos de suscripción
  # y de factura vuelven a leer la suscripción en Stripe (SyncService), así el orden no importa.
  class HandleWebhookService
    SUBSCRIPTION_EVENTS = %w[
      customer.subscription.created
      customer.subscription.updated
      customer.subscription.deleted
    ].freeze
    INVOICE_EVENTS = %w[invoice.paid invoice.payment_failed].freeze

    def initialize(event)
      @event = event
    end

    # Registro y efectos van en la misma transacción: si el procesamiento falla, el evento no
    # queda marcado y el reintento de Stripe lo vuelve a aplicar.
    def call
      ActiveRecord::Base.transaction(requires_new: true) do
        StripeEvent.create!(stripe_event_id: @event.id, event_type: @event.type, processed_at: Time.current)
        dispatch
      end
      true
    rescue ActiveRecord::RecordNotUnique
      false
    rescue ActiveRecord::RecordInvalid => e
      raise unless e.record.is_a?(StripeEvent) && e.record.errors.of_kind?(:stripe_event_id, :taken)

      false
    end

    private

    def dispatch
      object = @event.data.object

      case @event.type
      when "checkout.session.completed" then handle_checkout_completed(object)
      when *SUBSCRIPTION_EVENTS then SyncService.new(stripe_subscription: object["id"]).call
      when *INVOICE_EVENTS then sync_invoice(object)
      end
    end

    def handle_checkout_completed(session)
      stripe_subscription_id = session["subscription"]
      stripe_subscription_id = stripe_subscription_id["id"] if stripe_subscription_id.respond_to?(:keys)
      return if stripe_subscription_id.blank?

      company = find_company(session)
      return unless company

      subscription = company.subscription || company.build_subscription
      subscription.stripe_subscription_id = stripe_subscription_id
      subscription.save! if subscription.new_record? || subscription.changed?

      SyncService.new(stripe_subscription: stripe_subscription_id, subscription: subscription).call
    end

    def find_company(session)
      metadata = session["metadata"]
      company_id = metadata && metadata["company_id"]
      company_id = session["client_reference_id"] if company_id.blank?
      return if company_id.blank?

      Company.find_by(id: company_id)
    end

    # En la API reciente la suscripción de la factura está en parent.subscription_details.
    # (StripeObject no implementa dig.)
    def sync_invoice(invoice)
      details = invoice["parent"] && invoice["parent"]["subscription_details"]
      stripe_subscription_id = invoice["subscription"].presence || (details && details["subscription"])
      stripe_subscription_id = stripe_subscription_id["id"] if stripe_subscription_id.respond_to?(:keys)
      return if stripe_subscription_id.blank?

      SyncService.new(stripe_subscription: stripe_subscription_id).call
    end
  end
end
