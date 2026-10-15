# app/models/ticket.rb
class Ticket < ApplicationRecord
  belongs_to :work_order
  belongs_to :company

  enum :status, { pending: 0, paid: 1, voided: 2 }, default: :pending
  enum :payment_method, { cash: 0, card: 1, transfer: 2 }

  belongs_to :charged_by, polymorphic: true, optional: true
  belongs_to :voided_by, polymorphic: true, optional: true

  def status_label_text
    I18n.t("ticket.status.#{status}")
  end

  validates :folio, presence: true, uniqueness: true
  validates :total, presence: true, numericality: { greater_than_or_equal_to: 0 }

  validates :payment_method, :amount_received, :charged_by, :paid_at, presence: true, if: :paid?
  validates :amount_received, numericality: { greater_than_or_equal_to: ->(t) { t.total || 0 } }, allow_nil: true, if: :paid?
  validates :voided_at, :voided_by, :void_reason, presence: true, if: :voided?

  before_validation :reserve_folio, on: :create  # runs before validations so presence check passes
  after_create      :assign_folio                 # replaces temp value with ID-based folio

  private

  def reserve_folio
    self.folio = "T-#{SecureRandom.hex(8)}"
  end

  def assign_folio
    update_column(:folio, format("T-%06d", id))
  end
end
