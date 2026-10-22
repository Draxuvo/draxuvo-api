module Subscriptions
  # Levanta la suspensión cuando Stripe confirma el pago (spec 031): vuelve a activa con el plan que ya tiene.
  class ReactivateService
    # already_active: SyncService ya copió el estado active de Stripe; solo faltan limpiar y registrar.
    def initialize(subscription, already_active: false)
      @subscription = subscription
      @already_active = already_active
    end

    def call
      return @subscription unless @subscription.suspended? || @already_active

      Subscription.transaction do
        @subscription.update!(
          status: :active, suspended_at: nil, suspension_reason: nil, pending_invoice_url: nil,
          past_due_since: nil, past_due_notice_sent_at: nil, cancel_warning_sent_at: nil
        )
        @subscription.log_change!("reactivated")
      end
      @subscription
    end
  end
end
