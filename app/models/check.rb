# Cuenta de una mesa o de un pedido para llevar. Una cuenta cerrada o cancelada es de solo lectura.
class Check < ApplicationRecord
  belongs_to :company
  belongs_to :dining_table, optional: true
  belongs_to :opened_by, class_name: "User"
  belongs_to :waiter, class_name: "User"
  has_many :kitchen_orders, dependent: :destroy
  has_many :check_items, dependent: :destroy
  has_many :check_payments, dependent: :destroy
  has_one :ticket, dependent: :nullify

  enum :status, { open: 0, closed: 1, cancelled: 2 }, default: :open, prefix: true

  validates :opened_at, presence: true
  validate :table_or_takeout_name
  validate :table_belongs_to_company
  validate :table_is_free, on: :create

  # Solo se escribe mientras la fila guardada sigue abierta; así el cierre puede cambiar el estado una vez.
  def readonly?
    super || (persisted? && !status_in_database_open?)
  end

  def takeout? = dining_table_id.nil?

  def paid_total = check_payments.sum(:amount)

  def balance = total - paid_total

  def recalculate_total!
    update_columns(total: check_items.counted.sum("quantity * unit_price"), updated_at: Time.current)
  end

  def next_round_number = (kitchen_orders.maximum(:number) || 0) + 1

  private

  def status_in_database_open? = status_in_database.to_s == "open"

  def table_or_takeout_name
    errors.add(:base, :blank) if dining_table_id.blank? && takeout_name.to_s.strip.empty?
  end

  def table_belongs_to_company
    return unless dining_table && dining_table.company_id != company_id

    errors.add(:dining_table, :invalid)
  end

  def table_is_free
    return unless dining_table

    errors.add(:base, I18n.t("restaurant.errors.table_occupied")) unless dining_table.active?
  end
end
