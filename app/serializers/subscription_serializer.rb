# Contrato: specs/002-rebrand-suscripciones/contracts/api.md (GET /subscription) y
# specs/004-refactor-web-panel/contracts/api.md (managed_by_parent en sucursales).
# `company` es la empresa activa: en una sucursal, la suscripción es de la principal pero los
# módulos activos son los de la sucursal (cada empresa conserva sus disabled_modules).
class SubscriptionSerializer
  def initialize(subscription, company: nil)
    @s = subscription
    @company = company || subscription&.company
  end

  def as_json(*)
    return { plan: "basic", status: "expired", active_access: false, active_modules: [], available_modules: [] } if @s.nil?

    {
      id: @s.id,
      plan: @s.plan,
      billing_cycle: @s.billing_cycle,
      status: @s.status,
      cancel_at_period_end: @s.cancel_at_period_end,
      amount_cents: @s.amount_cents,
      iva_cents: @s.iva_cents,
      total_cents: @s.total_cents,
      trial_ends_at: @s.trial_ends_at,
      current_period_end: @s.current_period_end,
      active_modules: @company.active_modules.map(&:to_s),
      available_modules: @company.available_modules.map(&:to_s),
      managed_by_parent: @company.branch?,
      amount: @s.amount,
      iva_amount: @s.iva_amount,
      total_with_iva: @s.total_with_iva,
      iva_rate: Subscription::IVA_RATE,
      trial_days_remaining: @s.trial_days_remaining,
      current_period_start: @s.current_period_start,
      active_access: @s.active_access?,
      cancelled_at: @s.cancelled_at,
      created_at: @s.created_at,
      suspended_at: @s.suspended_at,
      suspension_reason: @s.suspension_reason,
      cancels_at: @s.cancels_at,
      pay_url: @s.suspended? ? @s.pending_invoice_url : nil,
      past_due_since: @s.past_due_since,
      grace_ends_at: @s.grace_ends_at
    }
  end
end
