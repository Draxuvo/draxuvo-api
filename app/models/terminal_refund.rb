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

  # En proceso en el proveedor: el barrido los consulta hasta una semana (después se revisan a mano en Mercado Pago).
  IN_FLIGHT_WATCH = 7.days
  scope :in_flight, -> { where(status: "requested").where("requested_at > ?", IN_FLIGHT_WATCH.ago) }

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

  # El proveedor confirmó la devolución: el reembolso queda hecho y la solicitud, reembolsada.
  def complete!(provider_refund_id: nil)
    update!(status: "done", completed_at: Time.current, provider_refund_id: provider_refund_id.presence || self.provider_refund_id,
            error_code: nil, error_message: nil)
    terminal_charge.update!(status: "refunded") unless terminal_charge.status == "refunded"
    TerminalEvent.log!(:refund_done, charge: terminal_charge, refund: self)
  end

  def as_payment_json = { status: status, amount: format("%.2f", amount), provider_refund_id: provider_refund_id, error_code: error_code,
      completed_at: completed_at }

  private

  def assign_key
    self.attempts ||= 1
    self.idempotency_key ||= key_for(attempts)
    self.requested_at ||= Time.current
  end

  def key_for(attempt) = "refund-#{terminal_charge_id}-#{attempt}"
end
