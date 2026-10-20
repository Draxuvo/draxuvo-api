# app/models/ticket.rb
class Ticket < ApplicationRecord
  belongs_to :work_order, optional: true
  belongs_to :check, optional: true
  belongs_to :company
  has_many :ticket_payments, -> { order(:id) }, dependent: :destroy

  enum :status, { pending: 0, paid: 1, voided: 2 }, default: :pending
  enum :payment_method, { cash: 0, card: 1, transfer: 2, mixed: 3 }

  belongs_to :charged_by, polymorphic: true, optional: true
  belongs_to :voided_by, polymorphic: true, optional: true

  def status_label_text
    I18n.t("ticket.status.#{status}")
  end

  validates :folio, presence: true, uniqueness: true
  validate :exactly_one_owner
  validates :total, presence: true, numericality: { greater_than_or_equal_to: 0 }

  validates :payment_method, :amount_received, :charged_by, :paid_at, presence: true, if: :paid?
  validates :amount_received, numericality: { greater_than_or_equal_to: ->(t) { t.total || 0 } }, allow_nil: true, if: :paid?
  validates :voided_at, :voided_by, :void_reason, presence: true, if: :voided?

  before_validation :reserve_folio, on: :create  # runs before validations so presence check passes
  after_create      :assign_folio                 # replaces temp value with ID-based folio

  private

  def exactly_one_owner
    errors.add(:base, :invalid) if work_order.nil? == check.nil?
  end

  def reserve_folio
    self.folio = "T-#{SecureRandom.hex(8)}"
  end

  def assign_folio
    update_column(:folio, format("T-%06d", id))
  end
end
