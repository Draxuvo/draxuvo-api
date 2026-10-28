# Canales por persona y empresa para los avisos de stock bajo (spec 045). Sin fila valen los valores por omisión.
class NotificationPreference < ApplicationRecord
  belongs_to :user
  belongs_to :company

  validates :user_id, uniqueness: { scope: :company_id }
  validate :whatsapp_needs_phone

  # Preferencia de `user` en `company`, sin guardar nada si no existe.
  def self.for(user, company)
    find_by(user_id: user.id, company_id: company.id) || new(user: user, company: company)
  end

  private

  def whatsapp_needs_phone
    errors.add(:stock_whatsapp, :phone_required) if stock_whatsapp? && user&.phone.blank?
  end
end
