# Un tipo de mensaje de WhatsApp que manda Draxuvo (spec 047): código de verificación, aviso de stock bajo o ticket.
# Cada uno tiene su interruptor y, si usa plantilla de Meta, su plantilla con el estado que Meta le da.
class WhatsappMessageType < ApplicationRecord
  KINDS = %w[verification_code stock_alert ticket].freeze
  TEMPLATE_STATUSES = %w[unknown approved pending rejected not_found incompatible].freeze

  validates :kind, inclusion: { in: KINDS }, uniqueness: true
  validates :template_name, format: { with: /\A[a-z0-9_]{1,512}\z/ }, allow_blank: true
  validates :template_language, format: { with: /\A[a-z]{2}(_[A-Z]{2})?\z/ }
  validates :template_status, inclusion: { in: TEMPLATE_STATUSES }
  validate :tickets_have_no_template
  validate :enabling_is_allowed, if: -> { will_save_change_to_enabled?(to: true) }

  # Crea los tres tipos con los nombres sugeridos si faltan (primer uso).
  def self.ensure_all!
    KINDS.each do |kind|
      next if exists?(kind: kind)

      definition = Whatsapp::MessageTypes.fetch(kind)
      create!(kind: kind, template_name: definition.suggested_name, template_language: definition.suggested_language || "es_MX")
    end
    order(:id)
  end

  def uses_template? = kind != "ticket"

  # Por qué no se puede encender (nil si se puede): not_connected, connection_error, template_not_approved o template_incompatible.
  def blocked_reason(connection = WhatsappConnection.current)
    return "connection_error" if connection.error?
    return "not_connected" unless connection.connected?
    return nil unless uses_template?
    return "template_incompatible" if template_status == "incompatible"

    template_status == "approved" ? nil : "template_not_approved"
  end

  def can_enable?(connection = WhatsappConnection.current) = blocked_reason(connection).nil?

  private

  def tickets_have_no_template
    errors.add(:template_name, :present) if kind == "ticket" && template_name.present?
  end

  def enabling_is_allowed
    reason = blocked_reason
    errors.add(:enabled, reason.to_sym) if reason
  end
end
