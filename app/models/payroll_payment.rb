# Línea de una corrida: lo que se le paga a un empleado en ese periodo (spec 037). Una vez pagada es inmutable.
class PayrollPayment < ApplicationRecord
  belongs_to :company
  belongs_to :payroll_run
  belongs_to :employee, optional: true
  belongs_to :paid_by, class_name: "User", optional: true
  has_many :adjustments, class_name: "PayrollAdjustment", dependent: :destroy

  enum :status, { pending: 0, paid: 1 }, default: :pending
  # `method` choca con Object#method, por eso la columna se llama payment_method.
  enum :payment_method, { cash: 0, transfer: 1, other: 2 }, prefix: :via

  validates :employee_name, presence: true
  validates :days_paid, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :reference, length: { maximum: 80 }
  validate :days_paid_within_period
  validate :paid_on_not_future, if: :paid?
  validate :immutable_once_paid, on: :update
  # Un pago hecho no se borra; solo se va con la empresa o con su corrida (cascada).
  before_destroy { throw :abort if paid? && !destroyed_by_association }

  private

  def days_paid_within_period
    errors.add(:days_paid, :invalid) if days_paid && period_days && days_paid > period_days
  end

  def paid_on_not_future
    errors.add(:paid_on, :invalid) if paid_on.blank? || paid_on > Time.zone.today
  end

  # Un pago hecho no se edita (R8): las correcciones son ajustes en una corrida nueva.
  def immutable_once_paid
    errors.add(:base, I18n.t("payroll.errors.readonly")) if status_in_database == "paid" && changed?
  end
end
