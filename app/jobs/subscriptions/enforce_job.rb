module Subscriptions
  # Reloj de la falta de pago (spec 031, R4); Stripe no avisa de nuestros plazos:
  # - past_due con más de 7 días sin pagar → suspendida (payment_overdue).
  # - suspendida con más de 23 días → aviso de cancelación (una sola vez).
  # - suspendida con más de 30 días → cancelada (Stripe y local) y registro auto_cancelled.
  class EnforceJob < ApplicationJob
    queue_as :default

    def perform
      suspend_overdue
      warn_before_cancel
      cancel_long_suspended
    end

    private

    def suspend_overdue
      Subscription.past_due.where(past_due_since: ...Subscription::GRACE_DAYS.days.ago).find_each do |subscription|
        SuspendService.new(subscription, reason: "payment_overdue").call
      end
    end

    def warn_before_cancel
      Subscription.suspended.where(cancel_warning_sent_at: nil)
                  .where(suspended_at: ...Subscription::CANCEL_WARNING_DAYS.days.ago).find_each do |subscription|
        NotifyService.new(subscription, "cancel_warning").call
      end
    end

    def cancel_long_suspended
      Subscription.suspended.where(suspended_at: ...Subscription::CANCEL_AFTER_DAYS.days.ago).find_each do |subscription|
        reason = subscription.suspension_reason
        CancelService.new(subscription, immediate: true).call
        subscription.log_change!("auto_cancelled", reason: reason)
      end
    end
  end
end
