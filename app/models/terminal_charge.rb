# Solicitud de cobro en una terminal integrada (spec 069, data-model.md). Vive minutos: se crea pendiente, se manda al
# proveedor y, cuando el proveedor confirma, `TerminalCharges::Apply` registra el cobro con los servicios de siempre.
#
#   pending ──► approved ──► applied | unapplied ──► refunded
#      ├──► canceling ──► canceled | approved
#      ├──► declined | canceled | expired
#      └──► abandoned ──► unapplied (si se aprueba tarde)
class TerminalCharge < ApplicationRecord
  STATUSES = %w[pending canceling approved applied unapplied declined canceled expired abandoned refunded].freeze
  OPEN = %w[pending canceling].freeze
  # Terminaron sin cobro en Draxuvo pero se siguen vigilando un rato por si el proveedor las aprueba tarde (SC-006).
  LATE = %w[abandoned expired canceled].freeze
  FINAL = %w[applied declined canceled expired refunded].freeze
  OWNER_TYPES = %w[work_order sale check].freeze
  # Margen tras `expires_at` para dar por vencida una solicitud sin respuesta (research R5, I3).
  EXPIRY_GRACE = 2.minutes
  # Hasta cuándo se sigue consultando una abandonada, por si se aprueba tarde (research R5, G1).
  ABANDONED_WATCH = 15.minutes
  TIMEOUT = 3.minutes

  belongs_to :company
  belongs_to :payment_terminal
  belongs_to :terminal_connection
  belongs_to :created_by, class_name: "User"
  belongs_to :work_order, optional: true
  belongs_to :sale, optional: true
  belongs_to :check, optional: true
  belongs_to :ticket_payment, optional: true
  belongs_to :check_payment, optional: true
  has_one :terminal_refund, dependent: :restrict_with_error

  validates :status, inclusion: { in: STATUSES }
  validates :amount, numericality: { greater_than: 0 }
  validate :exactly_one_owner

  before_validation :generate_references, on: :create

  scope :open, -> { where(status: OPEN) }
  scope :unapplied, -> { where(status: "unapplied") }
  # Pagos sin aplicar que aún piden atención: ni reembolsados ni marcados atendidos (FR-035).
  scope :unapplied_pending, -> { unapplied.where.not(id: TerminalRefund.where(status: %w[done skipped]).select(:terminal_charge_id)) }
  # Las que el barrido debe consultar: abiertas sin sincronizar hace 30 s, y abandonadas aún vigiladas (research R5).
  scope :due_for_sync, lambda {
    stale = where("last_synced_at IS NULL OR last_synced_at < ?", 30.seconds.ago).where.not(provider_order_id: nil)
    stale.where(status: OPEN).or(stale.where(status: LATE).where("expires_at > ?", ABANDONED_WATCH.ago))
         .or(stale.where(id: TerminalRefund.in_flight.select(:terminal_charge_id)))
  }

  def open? = OPEN.include?(status)
  def pending? = status == "pending"
  def canceling? = status == "canceling"
  def abandoned? = status == "abandoned"
  def unapplied? = status == "unapplied"
  def applied? = status == "applied"

  def owner = work_order || sale || check

  def owner_type
    return "work_order" if work_order_id
    return "sale" if sale_id

    "check" if check_id
  end

  # ¿Pasó su tiempo más el margen sin que el proveedor la diera por vencida?
  def overdue?(now = Time.current) = expires_at + EXPIRY_GRACE < now

  # La solicitud abierta de un dueño, si hay (para los bloqueos de venta, orden y cuenta: research R6).
  def self.open_for(owner)
    column = case owner
    when WorkOrder then :work_order_id
    when Sale then :sale_id
    when Check then :check_id
    end
    column ? open.find_by(column => owner.id) : nil
  end

  # 422 `terminal_charge_pending` si el dueño tiene una solicitud abierta.
  def self.ensure_none_open!(owner)
    pending = open_for(owner)
    return unless pending

    raise ApiErrors::UnprocessableEntityError.new(
      message: I18n.t("terminal_charge.errors.terminal_charge_pending"),
      details: { code: "terminal_charge_pending", terminal_charge_id: pending.id }
    )
  end

  private

  def generate_references
    self.idempotency_key ||= SecureRandom.uuid
    self.external_reference ||= "dx-#{company_id}-#{SecureRandom.alphanumeric(16)}"
    self.expires_at ||= TIMEOUT.from_now
  end

  def exactly_one_owner
    count = [ work_order_id, sale_id, check_id ].compact.size
    errors.add(:base, :invalid) unless count == 1
  end
end
