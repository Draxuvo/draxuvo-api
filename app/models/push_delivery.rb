# Bitácora de avisos push (spec 057, FR-023): una fila por persona y aviso, con el resultado y los tickets de Expo
# (`[{ "id", "device_id" }]`). Nunca guarda el token del dispositivo.
class PushDelivery < ApplicationRecord
  KINDS = %w[check_ready work_order_assigned operational_alert low_stock].freeze
  STATUSES = %w[sent skipped_preference off_shift no_devices invalid_device failed expired].freeze
  RETENTION = 90.days

  belongs_to :company
  belongs_to :user, optional: true

  validates :kind, inclusion: { in: KINDS }
  validates :status, inclusion: { in: STATUSES }
  validates :subject_key, presence: true, length: { maximum: 200 }

  scope :sent, -> { where(status: "sent") }
end
