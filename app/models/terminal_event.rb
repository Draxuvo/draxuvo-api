# Bitácora de la terminal integrada (spec 069, FR-029): conexiones, terminales, solicitudes y reembolsos. Solo inserción y
# nunca guarda tokens ni datos de tarjeta (salvo los últimos 4).
class TerminalEvent < ApplicationRecord
  KINDS = %w[connected disconnected connection_error token_refreshed device_linked device_unlinked device_prepared
             charge_created charge_approved charge_applied charge_unapplied charge_declined charge_canceled charge_expired
             charge_abandoned refund_requested refund_done refund_rejected refund_skipped webhook_ignored].freeze
  # Claves que nunca se guardan en `data`, a cualquier profundidad.
  SECRET_PATTERN = /token|secret|password|code_verifier/i

  belongs_to :company, optional: true
  belongs_to :terminal_connection, optional: true
  belongs_to :payment_terminal, optional: true
  belongs_to :terminal_charge, optional: true
  belongs_to :terminal_refund, optional: true
  belongs_to :user, optional: true

  validates :kind, inclusion: { in: KINDS }

  # Registra un evento. Las referencias (conexión, terminal, solicitud, reembolso) llenan `company` si no se pasa.
  def self.log!(kind, company: nil, user: nil, connection: nil, terminal: nil, charge: nil, refund: nil, **data)
    company ||= (charge || refund || terminal || connection)&.company
    create!(kind: kind.to_s, company: company, user: user, terminal_connection: connection, payment_terminal: terminal,
            terminal_charge: charge, terminal_refund: refund, data: scrub(data))
  end

  def self.scrub(value)
    case value
    when Hash then value.each_with_object({}) { |(key, inner), out| out[key.to_s] = scrub(inner) unless key.to_s.match?(SECRET_PATTERN) }
    when Array then value.map { |inner| scrub(inner) }
    else value
    end
  end

  # Solo inserción: una vez guardado no se edita ni se borra.
  def readonly? = persisted? || super
end
