# Terminal de cobro del negocio (spec 015). Con pagos no se borra: se desactiva (FR-019).
class PaymentTerminal < ApplicationRecord
  PROVIDERS = %w[bbva banorte santander banamex getnet mercado_pago clip other].freeze

  belongs_to :company
  has_many :ticket_payments, foreign_key: :terminal_id, dependent: :restrict_with_error, inverse_of: :terminal
  has_many :check_payments, foreign_key: :terminal_id, dependent: :restrict_with_error, inverse_of: :terminal

  normalizes :name, with: ->(name) { name.strip }

  validates :name, presence: true, length: { maximum: 60 }, uniqueness: { scope: :company_id, case_sensitive: false }
  validates :provider, inclusion: { in: PROVIDERS }

  scope :active, -> { where(active: true) }

  def provider_label = I18n.t("payment_terminal.providers.#{provider}")

  def payments_count = ticket_payments.count + check_payments.count

  # Una terminal usable en un pago nuevo: de la empresa y activa.
  def self.usable_for(company, id)
    company.payment_terminals.active.find_by(id: id)
  end
end
