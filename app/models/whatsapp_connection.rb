# La conexión de WhatsApp Business de toda la plataforma: una sola fila (spec 047). La llave va cifrada en reposo y
# nunca se serializa; para mostrarla se usa `token_hint` (últimos 4 caracteres).
class WhatsappConnection < ApplicationRecord
  STATUSES = %w[not_connected connected error].freeze
  DIGITS = /\A\d{6,20}\z/

  encrypts :access_token

  validates :status, inclusion: { in: STATUSES }
  validates :phone_number_id, :waba_id, format: { with: DIGITS }, allow_nil: true
  validate :enabled_needs_a_connection, if: -> { will_save_change_to_enabled?(to: true) }

  # La única fila de la plataforma; se crea en el primer uso.
  def self.current = first || create!

  def connected? = status == "connected"

  def error? = status == "error"

  # Asignar la llave guarda también sus últimos 4 caracteres para poder enmascararla sin descifrarla.
  def access_token=(value)
    super
    self.token_hint = value.to_s.strip.last(4).presence
  end

  # ¿Hay una llave guardada? Se mira el texto cifrado: no descifra, así que funciona aunque la llave de cifrado haya cambiado.
  def token_present? = read_attribute_before_type_cast("access_token").present?

  # La llave en claro, o nil si no hay o ya no se puede descifrar (por ejemplo, tras rotar SECRET_KEY_BASE).
  def token
    access_token
  rescue ActiveRecord::Encryption::Errors::Decryption
    nil
  end

  # ¿Hay una llave guardada que ya no se puede leer? (hay que capturarla otra vez)
  def token_unreadable? = token_present? && token.nil?

  # Borra la llave y los datos de conexión, apaga el canal y toma el control del panel (`managed`):
  # a partir de aquí las variables de entorno ya no se usan. No toca las plantillas elegidas.
  def disconnect!
    transaction do
      update!(access_token: nil, token_hint: nil, phone_number_id: nil, waba_id: nil, verified_name: nil,
              display_phone_number: nil, status: "not_connected", error_code: nil, error_message: nil, last_verified_at: nil,
              enabled: false, managed: true, problem_notified_at: nil)
      WhatsappMessageType.update_all(enabled: false, updated_at: Time.current)
    end
  end

  # Nunca incluye la llave (ni cifrada) al serializar.
  def serializable_hash(options = nil)
    options = (options || {}).dup
    options[:except] = Array(options[:except]) + %w[access_token]
    super(options)
  end

  private

  def enabled_needs_a_connection
    errors.add(:enabled, :not_connected) unless connected?
  end
end
