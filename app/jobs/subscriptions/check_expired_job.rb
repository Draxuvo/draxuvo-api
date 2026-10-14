module Subscriptions
  # Expira solo las pruebas gratuitas vencidas. Las suscripciones pagadas (active, past_due)
  # cambian de estado únicamente por webhook de Stripe (FR-007), así que aquí no se tocan.
  class CheckExpiredJob < ApplicationJob
    queue_as :default

    def perform
      Subscription.trialing
                  .where(trial_ends_at: ...Time.current)
                  .update_all(status: Subscription.statuses[:expired], updated_at: Time.current)
    end
  end
end
