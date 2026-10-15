# Respuesta guardada de una petición con cabecera Idempotency-Key (spec 011, FR-027).
# Un reenvío con la misma llave devuelve esta respuesta en vez de repetir el efecto.
class IdempotencyKey < ApplicationRecord
  MAX_KEY_LENGTH = 64

  belongs_to :user

  validates :key, presence: true, length: { maximum: MAX_KEY_LENGTH }, uniqueness: { scope: :user_id }
  validates :request_method, :request_path, :response_status, :response_body, presence: true
end
