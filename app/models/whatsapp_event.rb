# Historial de la configuración de WhatsApp (spec 047): quién cambió qué, las pruebas, los apagados automáticos y los
# avisos al equipo. Solo inserción, y nunca guarda secretos.
class WhatsappEvent < ApplicationRecord
  ACTIONS = %w[connected token_replaced disconnected channel_on channel_off type_on type_off template_changed verified
               test_sent auto_off connection_error alert_sent].freeze
  TARGETS = %w[connection verification_code stock_alert ticket].freeze
  RESULTS = %w[ok failed].freeze
  # Claves que nunca se guardan en `data`, a cualquier profundidad.
  SECRET_KEYS = %w[token access_token secret].freeze

  belongs_to :user, optional: true

  validates :action, inclusion: { in: ACTIONS }
  validates :target, inclusion: { in: TARGETS }
  validates :result, inclusion: { in: RESULTS }

  scope :recent, -> { order(created_at: :desc, id: :desc) }

  # Registra un evento; borra de `data` cualquier clave secreta para que ningún llamador pueda guardar la llave por error.
  def self.log!(action:, target:, user: nil, result: "ok", data: {}, meta_code: nil)
    create!(action: action.to_s, target: target.to_s, user: user, result: result.to_s, data: scrub(data), meta_code: meta_code&.to_s)
  end

  # «5512345678» → «••••5678»
  def self.mask_phone(phone)
    digits = phone.to_s.gsub(/\D/, "")
    digits.empty? ? nil : "••••#{digits.last(4)}"
  end

  def self.scrub(value)
    case value
    when Hash then value.to_h { |key, inner| [ key.to_s, scrub(inner) ] }.except(*SECRET_KEYS)
    when Array then value.map { |inner| scrub(inner) }
    else value
    end
  end

  # Solo inserción: una vez guardado no se edita ni se borra.
  def readonly? = persisted? || super
end
