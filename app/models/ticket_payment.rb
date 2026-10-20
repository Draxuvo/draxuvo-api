# Un pago del cobro de una orden (spec 015). No se edita: un error se corrige anulando el cobro,
# que solo marca voided_at (R6).
class TicketPayment < ApplicationRecord
  belongs_to :company
  belongs_to :ticket
  belongs_to :created_by, class_name: "User"
  belongs_to :terminal, class_name: "PaymentTerminal", optional: true, inverse_of: :ticket_payments

  enum :payment_method, { cash: 0, card: 1, transfer: 2 }
  enum :source, { manual: 0 }, default: :manual

  scope :active, -> { where(voided_at: nil) }

  # El formato anterior del cobro (un método, sin referencia) sigue llegando de la app instalada (research R2).
  attr_accessor :legacy

  before_validation :compute_change

  validates :amount, numericality: { greater_than: 0 }
  validates :amount_received, numericality: { greater_than_or_equal_to: ->(p) { p.amount || 0 } }, if: :cash?
  validates :reference, presence: true, if: -> { transfer? && !legacy }
  validates :reference, length: { maximum: 60 }
  validates :authorization_code, format: { with: /\A[a-zA-Z0-9]{1,12}\z/ }, allow_blank: true
  validates :card_last4, format: { with: /\A\d{4}\z/ }, allow_blank: true
  validate :card_fields_only_on_card
  validate :terminal_usable, on: :create

  def readonly? = super || (persisted? && (changed - %w[voided_at updated_at]).any?)

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

  def card_fields_only_on_card
    return if card?

    errors.add(:terminal, :invalid) if terminal_id
    errors.add(:authorization_code, :invalid) if authorization_code.present?
    errors.add(:card_last4, :invalid) if card_last4.present?
  end

  def terminal_usable
    return unless terminal_id

    errors.add(:terminal, :invalid) unless terminal && terminal.active? && terminal.company_id == company_id
  end
end
