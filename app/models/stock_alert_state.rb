# Estado de aviso de un producto con stock bajo (spec 045): detectado → avisado → se borra al reponerse (rearme).
class StockAlertState < ApplicationRecord
  belongs_to :company
  belongs_to :product

  # Espera tras detectar el bajón para juntar importaciones y conteos en un solo aviso.
  GRACE = 5.minutes

  validates :detected_at, presence: true
  validates :product_id, uniqueness: true

  scope :pending, -> { where(notified_at: nil) }
  scope :notified, -> { where.not(notified_at: nil) }
end
