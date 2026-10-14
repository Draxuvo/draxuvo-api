class Subscription < ApplicationRecord
  belongs_to :company

  TRIAL_DAYS = 30
  IVA_RATE = 0.16

  # Precios en Plan (app/models/plan.rb). amount_cents es el precio base SIN IVA, en centavos de MXN.
  enum :plan, { basic: 0, pro: 1, enterprise: 2 }
  enum :status, { trialing: 0, active: 1, past_due: 2, cancelled: 3, expired: 4 }
  enum :billing_cycle, { monthly: 0, annual: 1 }

  validates :plan, :status, :billing_cycle, presence: true
  validates :amount_cents, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :company_id, uniqueness: true

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
  def active_access?
    (trialing? && trial_ends_at&.future?) || active? || past_due?
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
