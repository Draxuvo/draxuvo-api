# Aviso de stock bajo enviado a una persona por un canal (spec 045). Solo inserción: sirve para auditar entregas y
# para no repetir el resumen del día (índice único parcial de `daily`).
class AlertDelivery < ApplicationRecord
  belongs_to :company
  belongs_to :user, optional: true

  CHANNELS = %w[email whatsapp].freeze
  KINDS = %w[immediate daily].freeze
  # unavailable: el canal no está configurado (p. ej. WhatsApp sin plantilla); simulated: empresa de demo.
  STATUSES = %w[sent failed unavailable simulated].freeze

  validates :channel, inclusion: { in: CHANNELS }
  validates :kind, inclusion: { in: KINDS }
  validates :status, inclusion: { in: STATUSES }
  validates :sent_on, presence: true
end
