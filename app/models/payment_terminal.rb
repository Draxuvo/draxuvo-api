# Terminal de cobro del negocio (spec 015). Con pagos no se borra: se desactiva (FR-019).
# Spec 069: una terminal puede estar **integrada** (ligada a una conexión con un proveedor y a un dispositivo de esa cuenta)
# o ser **manual** como hoy. Una integrada toma el proveedor de su conexión y no lo cambia.
class PaymentTerminal < ApplicationRecord
  PROVIDERS = %w[bbva banorte santander banamex getnet mercado_pago clip other].freeze

  belongs_to :company
  belongs_to :terminal_connection, optional: true
  has_many :ticket_payments, foreign_key: :terminal_id, dependent: :restrict_with_error, inverse_of: :terminal
  has_many :check_payments, foreign_key: :terminal_id, dependent: :restrict_with_error, inverse_of: :terminal
  has_many :terminal_charges, dependent: :restrict_with_error

  normalizes :name, with: ->(name) { name.strip }

  validates :name, presence: true, length: { maximum: 60 }, uniqueness: { scope: :company_id, case_sensitive: false }
  validates :provider, inclusion: { in: PROVIDERS }
  validates :device_id, uniqueness: { scope: :provider }, allow_nil: true
  validate :connection_of_same_company
  validate :integrated_provider_fixed, on: :update
  validate :no_open_charge_when_deactivating, on: :update
  before_destroy :ensure_no_open_charge, prepend: true

  scope :active, -> { where(active: true) }

  def integrated? = terminal_connection_id.present? && device_id.present?

  # Integrada, activa y con la conexión al corriente: se le pueden mandar cobros (spec 069).
  def chargeable? = active? && integrated? && terminal_connection&.connected?

  def kind = integrated? ? "integrated" : "manual"

  def open_charge = terminal_charges.open.first

  # La deja manual: quita la conexión y el dispositivo; no toca sus pagos (spec 069, unlink).
  def unlink!
    update!(terminal_connection: nil, device_id: nil, device_mode: nil)
  end

  def provider_label = I18n.t("payment_terminal.providers.#{provider}")

  def payments_count = ticket_payments.count + check_payments.count

  # Una terminal usable en un pago nuevo: de la empresa y activa.
  def self.usable_for(company, id)
    company.payment_terminals.active.find_by(id: id)
  end

  private

  def connection_of_same_company
    return unless terminal_connection

    errors.add(:terminal_connection, :invalid) unless terminal_connection.company_id == company_id
  end

  # Una integrada usa el proveedor de su conexión (spec 069: `integrated_terminal`).
  def integrated_provider_fixed
    return unless will_save_change_to_provider? && integrated? && !will_save_change_to_terminal_connection_id?

    errors.add(:provider, I18n.t("payment_terminal.errors.integrated_terminal"))
  end

  def no_open_charge_when_deactivating
    return unless will_save_change_to_active?(to: false) || (will_save_change_to_terminal_connection_id? && terminal_connection_id.nil?)

    errors.add(:base, I18n.t("terminal_charge.errors.terminal_charge_pending")) if terminal_charges.open.exists?
  end

  def ensure_no_open_charge
    return unless terminal_charges.open.exists?

    errors.add(:base, I18n.t("terminal_charge.errors.terminal_charge_pending"))
    throw :abort
  end
end
