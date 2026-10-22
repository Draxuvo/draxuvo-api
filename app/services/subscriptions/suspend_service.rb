module Subscriptions
  # Suspende la suscripción por falta de pago (spec 031): bloquea la operación hasta que se pague.
  # reason: "plan_change" (cambio de plan sin pago) o "payment_overdue" (cobro normal sin pagar tras la gracia).
  # Idempotente: una suscripción ya suspendida no se vuelve a avisar ni a registrar.
  class SuspendService
    def initialize(subscription, reason:, invoice_url: nil)
      @subscription = subscription
      @reason = reason.to_s
      @invoice_url = invoice_url
    end

    def call
      return @subscription if @subscription.suspended?

      Subscription.transaction do
        @subscription.update!(
          status: :suspended, suspended_at: Time.current, suspension_reason: @reason,
          pending_invoice_url: @invoice_url.presence || @subscription.pending_invoice_url, past_due_since: nil
        )
        @subscription.log_change!("suspended", reason: @reason)
      end
      NotifyService.new(@subscription, "suspended").call
      @subscription
    end
  end
end
