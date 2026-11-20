# Reembolso total de un pago integrado (spec 069, FR-031 a FR-036, research R8). A lo más uno por solicitud. La llave de
# idempotencia cambia solo tras un rechazo confirmado: mientras está `requested` (o sin respuesta) se reutiliza, así un
# reintento nunca devuelve dos veces.
class TerminalRefund < ApplicationRecord
  STATUSES = %w[requested done rejected skipped].freeze

  belongs_to :company
  belongs_to :terminal_charge
  belongs_to :ticket_payment, optional: true
  belongs_to :requested_by, class_name: "User"

  validates :status, inclusion: { in: STATUSES }
  validates :amount, numericality: { greater_than: 0 }
  validates :terminal_charge_id, uniqueness: true

  before_validation :assign_key, on: :create

  def done? = status == "done"
  def skipped? = status == "skipped"
  def rejected? = status == "rejected"
  def requested? = status == "requested"

  # ¿Ya no hay que pedir nada? (`done` o `skipped`)
  def settled? = done? || skipped?

  # Prepara un nuevo intento tras un rechazo confirmado: otra llave, para que el proveedor no repita su respuesta.
  def next_attempt!
    update!(attempts: attempts + 1, idempotency_key: key_for(attempts + 1), status: "requested", error_code: nil,
            error_message: nil, requested_at: Time.current)
  end

  def as_payment_json = { status: status, amount: amount.to_s, completed_at: completed_at, error_code: error_code }

  private

  def assign_key
    self.attempts ||= 1
    self.idempotency_key ||= key_for(attempts)
    self.requested_at ||= Time.current
  end

  def key_for(attempt) = "refund-#{terminal_charge_id}-#{attempt}"
end
