# Alerta de tiempo pospuesta por un plazo fijo (spec 045). Vale para todos los jefes de la empresa.
# La `subject_key` incluye el origen del elemento: si el elemento se rehace (mesa reocupada), no hereda la posposición.
class AlertSnooze < ApplicationRecord
  belongs_to :company
  belongs_to :user, optional: true

  # `low_stock` no se pospone: su ruido ya se controla con la regla de no repetir el aviso.
  KINDS = %w[kitchen_wait kitchen_preparing work_order_stalled table_open].freeze
  MINUTES = [ 30, 60, 120 ].freeze

  validates :kind, inclusion: { in: KINDS }
  validates :subject_key, :snoozed_until, presence: true

  scope :active, -> { where(snoozed_until: Time.current..) }
  scope :expired, -> { where(snoozed_until: ...Time.current) }
end
