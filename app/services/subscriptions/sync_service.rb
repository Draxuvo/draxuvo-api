module Subscriptions
  # Vuelve a leer la suscripción en Stripe y copia su estado a la local (research R11, R12).
  # Así el resultado no depende del orden en que lleguen los eventos.
  class SyncService
    # R12. `incomplete` y los estados desconocidos conservan el estado anterior.
    STATUS_MAP = {
      "trialing" => :trialing,
      "active" => :active,
      "past_due" => :past_due,
      "unpaid" => :past_due,
      "canceled" => :cancelled,
      "incomplete_expired" => :cancelled
    }.freeze

    # stripe_subscription: id o objeto de Stripe; siempre se vuelve a leer.
    # subscription: registro local a usar (p. ej. al completar el checkout); si falta, se busca por
    # stripe_subscription_id y, si no existe, no se hace nada.
    def initialize(stripe_subscription:, subscription: nil)
      @stripe_subscription_id = stripe_subscription.respond_to?(:id) ? stripe_subscription.id : stripe_subscription.to_s
      @subscription = subscription
    end

    def call
      return if @stripe_subscription_id.blank?

      subscription = @subscription || Subscription.find_by(stripe_subscription_id: @stripe_subscription_id)
      return unless subscription

      stripe_sub = Stripe::Subscription.retrieve({ id: @stripe_subscription_id, expand: [ "items.data.price" ] })
      was_suspended = subscription.suspended?
      subscription.update!(attributes_from(stripe_sub, subscription))
      finish_suspension(subscription, was_suspended)
      subscription
    end

    private

    def attributes_from(stripe_sub, subscription)
      item = stripe_sub.items&.data&.first
      attrs = {
        stripe_subscription_id: stripe_sub.id,
        cancel_at_period_end: stripe_sub["cancel_at_period_end"] ? true : false,
        current_period_start: timestamp(stripe_sub["current_period_start"] || item&.[]("current_period_start")),
        current_period_end: timestamp(stripe_sub["current_period_end"] || item&.[]("current_period_end"))
      }.compact
      attrs.merge!(status_attributes(stripe_sub, subscription))
      attrs.merge!(plan_attributes(item&.price&.lookup_key))
    end

    def status_attributes(stripe_sub, subscription)
      status = STATUS_MAP[stripe_sub.status.to_s]
      return {} unless status
      # Suspendida (spec 031) sigue así mientras Stripe no confirme el pago: no la baja a past_due.
      return {} if subscription.suspended? && status == :past_due

      attrs = { status: status }
      attrs.merge!(past_due_attributes(status, subscription))
      if status == :cancelled
        attrs[:cancelled_at] = subscription.cancelled_at || timestamp(stripe_sub["canceled_at"]) || Time.current
      else
        attrs[:cancelled_at] = nil
      end
      attrs[:trial_ends_at] = nil if status == :active
      attrs
    end

    # La gracia de 7 días de un cobro normal fallido corre desde el primer past_due (spec 031).
    def past_due_attributes(status, subscription)
      return { past_due_since: nil } unless status == :past_due

      { past_due_since: subscription.past_due_since || Time.current }
    end

    # Al pagar, Stripe vuelve a decir active: se levanta la suspensión; si canceló, se registra el estado final.
    def finish_suspension(subscription, was_suspended)
      return unless was_suspended
      return ReactivateService.new(subscription, already_active: true).call if subscription.active?

      subscription.update!(suspended_at: nil, suspension_reason: nil, pending_invoice_url: nil) if subscription.cancelled?
    end

    # Un lookup_key desconocido no toca plan, ciclo ni monto.
    def plan_attributes(lookup_key)
      plan_key, cycle = Plan.parse_lookup_key(lookup_key)
      return {} unless plan_key

      {
        plan: plan_key,
        billing_cycle: cycle,
        amount_cents: Plan.find(plan_key).amount_cents(cycle),
        stripe_price_lookup_key: lookup_key
      }
    end

    def timestamp(value)
      value.present? ? Time.zone.at(value.to_i) : nil
    end
  end
end
