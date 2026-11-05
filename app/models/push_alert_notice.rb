# Alerta operativa ya avisada por push (spec 057, FR-012). Es por empresa, igual que la alerta y su posposición
# (spec 045). `rearm` queda en verdadero cuando la alerta se vio pospuesta: al terminar la posposición se avisa una vez más.
class PushAlertNotice < ApplicationRecord
  belongs_to :company

  validates :kind, :subject_key, :notified_at, presence: true
end
