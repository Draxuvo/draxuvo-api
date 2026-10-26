module Subscriptions
  # Cancela la suscripción (research R10).
  # - Por defecto programa la cancelación al fin del periodo: el acceso sigue hasta
  #   current_period_end y el webhook trae el estado final.
  # - immediate: true (borrado de una empresa) la cancela en el acto.
  class CancelService
    def initialize(subscription, immediate: false)
      @subscription = subscription
      @immediate = immediate
    end

    def call
      Demo::Guard.restrict!(:plan_change) unless @immediate
      @immediate ? cancel_now : cancel_at_period_end
      @subscription
    end

    private

    def stripe_id
      @subscription.stripe_subscription_id.presence
    end

    def cancel_at_period_end
      return @subscription unless stripe_id

      Stripe::Subscription.update(stripe_id, { cancel_at_period_end: true })
      @subscription.update!(cancel_at_period_end: true)
    end

    def cancel_now
      Stripe::Subscription.cancel(stripe_id) if stripe_id
      @subscription.update!(status: :cancelled, cancelled_at: Time.current, cancel_at_period_end: false)
    end
  end
end
