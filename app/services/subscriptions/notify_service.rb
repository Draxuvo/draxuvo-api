module Subscriptions
  # Avisos por correo a dueños y administradores de la empresa que paga (spec 031, R7).
  # kind: "past_due" (pago pendiente), "suspended" o "cancel_warning". Cada uno sale una sola vez.
  class NotifyService
    SENT_COLUMN = { "past_due" => :past_due_notice_sent_at, "cancel_warning" => :cancel_warning_sent_at }.freeze

    def initialize(subscription, kind)
      @subscription = subscription
      @kind = kind.to_s
    end

    def call
      column = SENT_COLUMN[@kind]
      return false if column && @subscription.public_send(column).present?

      recipients.each { |user| deliver(user) }
      @subscription.update_column(column, Time.current) if column
      true
    end

    private

    def company = @subscription.company

    def recipients
      company.user_companies.where(role: %i[owner admin]).includes(:user).map(&:user).compact.select(&:active?).uniq
    end

    def deliver(user)
      ResendMailer.subscription_notice(
        user: user, company_name: company.name, kind: @kind, plan: @subscription.plan,
        pay_url: @subscription.pending_invoice_url, grace_ends_at: @subscription.grace_ends_at,
        cancels_at: @subscription.cancels_at
      )
    end
  end
end
