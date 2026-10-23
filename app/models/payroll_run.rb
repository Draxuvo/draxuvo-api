# Corrida de nómina (spec 037): un periodo de pago de la empresa con una línea por empleado.
class PayrollRun < ApplicationRecord
  belongs_to :company
  belongs_to :created_by, class_name: "User"
  belongs_to :approved_by,  class_name: "User", optional: true
  belongs_to :cancelled_by, class_name: "User", optional: true
  has_many :payments, class_name: "PayrollPayment", dependent: :destroy
  # La bitácora es de solo inserción (readonly?): al descartar un borrador se borra en bloque, sin callbacks.
  has_many :events, class_name: "PayrollEvent", dependent: :delete_all

  enum :period_type, { weekly: 0, biweekly: 1, monthly: 2 }
  enum :status, { draft: 0, approved: 1, partial: 2, paid: 3, cancelled: 4 }, default: :draft

  validates :period_type, :starts_on, :ends_on, presence: true
  validate :period_length

  scope :for_year, ->(year) { where(starts_on: Date.new(year.to_i, 1, 1)..Date.new(year.to_i, 12, 31)) if year.present? }

  # Aprobada, parcial o pagada: ya tiene montos congelados.
  def frozen_amounts? = !draft? && !cancelled?

  def period_days = Payroll::Period.days(starts_on, ends_on)

  private

  def period_length
    return if starts_on.blank? || ends_on.blank? || period_type.blank?

    if ends_on < starts_on
      errors.add(:ends_on, :invalid)
    elsif period_days > Payroll::Period::MAX_DAYS.fetch(period_type.to_sym)
      errors.add(:ends_on, :invalid)
    end
  end
end
