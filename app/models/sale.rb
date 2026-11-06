# Venta de mostrador (spec 050). Abierta es un borrador de quien la abrió; cobrada genera un ticket; cancelada
# anula ese ticket. Cobrada y cancelada no admiten cambios de renglones ni de total.
class Sale < ApplicationRecord
  belongs_to :company
  belongs_to :opened_by, class_name: "User"
  belongs_to :charged_by, class_name: "User", optional: true
  belongs_to :cancelled_by, class_name: "User", optional: true
  belongs_to :returned_by, class_name: "User", optional: true
  has_many :sale_items, -> { order(:id) }, dependent: :destroy
  has_one :ticket, dependent: :nullify
  has_many :stock_movements, dependent: :nullify

  enum :status, { open: 0, paid: 1, cancelled: 2 }, default: :open, prefix: true

  validates :total, numericality: { greater_than_or_equal_to: 0 }
  validates :cancel_reason, :cancelled_at, :cancelled_by, presence: true, if: :status_cancelled?
  validates :paid_at, :charged_by, presence: true, if: -> { status_paid? || status_cancelled? }
  validate :items_frozen_unless_open, on: :update
  validate :submitted_only_while_open, on: :update

  scope :for_company, ->(company) { where(company_id: company.id) }
  # Spec 058: ventas que su cajero pasó a cobro y esperan a un jefe, de la más antigua a la más reciente.
  scope :queued, -> { status_open.where.not(submitted_at: nil).reorder(:submitted_at, :id) }

  # Lista para cobro (spec 058): abierta y pasada a cobro por quien la abrió. Si no, está en captura.
  def submitted? = status_open? && submitted_at.present?

  # La suma de los renglones es el total (no hay descuentos, spec 050).
  def recalculate_total!
    update!(total: sale_items.reload.sum(:subtotal))
  end

  private

  # Una venta cobrada o cancelada no cambia su total (solo pasa de cobrada a cancelada).
  def items_frozen_unless_open
    return if status_in_database == "open"
    return unless total_changed?

    errors.add(:base, :invalid)
  end

  # Solo una venta abierta se pasa a cobro.
  def submitted_only_while_open
    return unless submitted_at_changed? && submitted_at.present? && submitted_at_was.nil?
    return if status_in_database == "open"

    errors.add(:submitted_at, :invalid)
  end
end
