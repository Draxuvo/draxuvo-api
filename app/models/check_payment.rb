# Un pago sobre una cuenta. No se edita ni se borra: un error se corrige anulando el ticket.
class CheckPayment < ApplicationRecord
  belongs_to :company
  belongs_to :check
  belongs_to :created_by, class_name: "User"
  belongs_to :terminal, class_name: "PaymentTerminal", optional: true, inverse_of: :check_payments

  enum :payment_method, { cash: 0, card: 1, transfer: 2 }
  enum :source, { manual: 0 }, default: :manual

  validates :amount, numericality: { greater_than: 0 }
  validates :reference, presence: true, if: -> { card? || transfer? }
  validates :amount_received, numericality: { greater_than_or_equal_to: ->(p) { p.amount || 0 } }, if: :cash?
  validate :within_balance, on: :create
  validate :terminal_usable, on: :create

  before_validation :compute_change

  def readonly? = super || persisted?

  private

  def compute_change
    if cash?
      self.amount_received ||= amount
      self.change_given = amount_received - amount if amount && amount_received
    else
      self.amount_received = nil
      self.change_given = nil
    end
  end

  # Solo tarjeta, de la misma empresa y activa (spec 015, FR-022).
  def terminal_usable
    return unless terminal_id

    errors.add(:terminal, :invalid) unless card? && terminal&.active? && terminal.company_id == company_id
  end

  def within_balance
    return unless check && amount

    errors.add(:amount, I18n.t("restaurant.errors.exceeds_balance")) if amount > check.balance
  end
end
