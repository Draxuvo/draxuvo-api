class Subscription < ApplicationRecord
  belongs_to :company

  TRIAL_DAYS = 30
  IVA_RATE = 0.16
  # Cobro normal fallido: gracia con acceso y luego suspensión; suspendida: cancelación automática (spec 031).
  GRACE_DAYS = 7
  CANCEL_AFTER_DAYS = 30
  CANCEL_WARNING_DAYS = 23
  SUSPENSION_REASONS = %w[plan_change payment_overdue].freeze

  # Precios en Plan (app/models/plan.rb). amount_cents es el precio base SIN IVA, en centavos de MXN.
  enum :plan, { basic: 0, pro: 1, enterprise: 2 }
  enum :status, { trialing: 0, active: 1, past_due: 2, cancelled: 3, expired: 4, suspended: 5 }
  enum :billing_cycle, { monthly: 0, annual: 1 }

  validates :plan, :status, :billing_cycle, presence: true
  validates :amount_cents, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :company_id, uniqueness: true
  validates :suspension_reason, inclusion: { in: SUSPENSION_REASONS }, allow_nil: true

  has_many :subscription_changes, dependent: :destroy

  def self.start_trial!(company, plan:)
    create!(
      company: company,
      plan: Plan.find(plan).key,
      status: :trialing,
      billing_cycle: :monthly,
      amount_cents: 0,
      cancel_at_period_end: false,
      trial_ends_at: TRIAL_DAYS.days.from_now
    )
  end

  # Una cancelación programada (cancel_at_period_end) conserva el acceso hasta el fin del periodo.
  # Suspendida (spec 031) no tiene acceso: solo se puede ver el estado y pagar.
  def active_access?
    (trialing? && trial_ends_at&.future?) || active? || past_due?
  end

  # Fin de la gracia de un cobro normal fallido.
  def grace_ends_at
    past_due_since && past_due_since + GRACE_DAYS.days
  end

  # Cuándo se cancela sola una suscripción suspendida.
  def cancels_at
    suspended_at && suspended_at + CANCEL_AFTER_DAYS.days
  end

  # Registra un cambio de suscripción (quién, cuándo y qué).
  def log_change!(kind, actor: nil, from_plan: nil, to_plan: nil, reason: nil)
    subscription_changes.create!(company: company, actor: actor, kind: kind, from_plan: from_plan, to_plan: to_plan, reason: reason)
  end

  def trial_days_remaining
    return 0 unless trialing? && trial_ends_at
    [ (trial_ends_at.to_date - Date.current).to_i, 0 ].max
  end

  def iva_cents
    (amount_cents.to_i * IVA_RATE).round
  end

  def total_cents
    amount_cents.to_i + iva_cents
  end

  def amount
    amount_cents / 100.0
  end

  def iva_amount
    iva_cents / 100.0
  end

  def total_with_iva
    total_cents / 100.0
  end
end
