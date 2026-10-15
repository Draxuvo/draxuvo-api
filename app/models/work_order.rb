# app/models/work_order.rb
class WorkOrder < ApplicationRecord
  PHONE_FORMAT = /\A[0-9 +\-()]+\z/

  belongs_to :company
  belongs_to :employee, optional: true
  belongs_to :created_by, polymorphic: true
  has_many   :work_order_steps, -> { order(:position) }, dependent: :destroy
  has_many   :work_order_items, -> { order(:position) }, dependent: :destroy
  has_many   :work_order_attachments, dependent: :destroy
  has_many   :work_order_events, -> { order(:created_at) }, dependent: :destroy
  has_many   :products, through: :work_order_items
  has_one    :ticket, dependent: :destroy

  alias_method :steps, :work_order_steps
  alias_method :events, :work_order_events
  alias_method :attachments, :work_order_attachments

  enum :priority, { low: 0, medium: 1, high: 2, urgent: 3 }, default: :medium
  enum :status, {
    open:        0,
    in_progress: 1,
    done:        2,
    paid:        3,
    cancelled:   4
  }, default: :open

  scope :search, ->(q) {
    return all unless q.present?
    where("title ILIKE :q OR description ILIKE :q", q: "%#{q}%")
  }

  validates :title, presence: true
  validates :customer_phone, format: { with: PHONE_FORMAT }, length: { in: 7..20 }, allow_blank: true
  validates :cancel_reason, presence: true, if: :cancelled?
  validate  :employee_belongs_to_company
  before_update :reject_changes_when_locked

  # Una orden cobrada o cancelada no acepta cambios (FR-007)
  def locked?
    paid? || cancelled?
  end

  # Porcentaje de pasos hechos sobre pasos totales
  def progress
    total = work_order_steps.size
    return 0 if total.zero?
    done_count = work_order_steps.count { |s| s.done_at.present? }
    (done_count.to_f / total * 100).round
  end

  # Suma los subtotales (unit_price * quantity) de todos los conceptos que tengan precio
  def recalculate_total!
    new_total = work_order_items.reload.sum(&:subtotal)
    update_column(:total, new_total)
  end

  private

  def employee_belongs_to_company
    return if employee.nil? || employee.company_id == company_id
    errors.add(:employee, :invalid)
  end

  # Solo se permite la salida paid -> done (void_charge); cancelled no tiene salida.
  def reject_changes_when_locked
    before = status_in_database
    return unless %w[paid cancelled].include?(before)
    return if before == "paid" && status == "done" && (changed - %w[status updated_at]).empty?
    errors.add(:base, :locked)
    throw :abort
  end
end
