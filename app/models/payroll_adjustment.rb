# Bono o deducción de una línea de nómina (spec 037). Solo se captura con la corrida en borrador.
class PayrollAdjustment < ApplicationRecord
  belongs_to :company
  belongs_to :payroll_payment
  belongs_to :corrects_payment, class_name: "PayrollPayment", optional: true
  belongs_to :created_by, class_name: "User"

  enum :kind, { bonus: 0, deduction: 1 }

  validates :amount_cents, numericality: { only_integer: true, greater_than: 0 }
  validates :note, presence: true, length: { maximum: 200 }
  validate :run_is_draft
  validate :valid_correction, if: :corrects_payment

  before_destroy :ensure_draft_run, unless: :destroyed_by_association

  private

  def ensure_draft_run
    return if payroll_payment.payroll_run.draft?

    errors.add(:base, I18n.t("payroll.errors.readonly"))
    throw :abort
  end

  def run_is_draft
    errors.add(:base, I18n.t("payroll.errors.readonly")) unless payroll_payment&.payroll_run&.draft?
  end

  def valid_correction
    original = corrects_payment
    ok = original.paid? && original.company_id == company_id && original.employee_id.present? &&
         original.employee_id == payroll_payment.employee_id
    errors.add(:corrects_payment_id, :invalid) unless ok
  end
end
