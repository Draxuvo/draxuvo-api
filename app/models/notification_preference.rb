# Canal de correo por persona y empresa para los avisos de stock bajo (spec 045). Sin fila valen los valores por omisión
# (correo encendido). `stock_whatsapp` es un valor histórico (spec 048): se conserva en las filas existentes pero ya no
# se lee, no se escribe ni se valida (antes exigía teléfono), para que una preferencia vieja nunca bloquee un guardado.
class NotificationPreference < ApplicationRecord
  belongs_to :user
  belongs_to :company

  validates :user_id, uniqueness: { scope: :company_id }

  # Preferencia de `user` en `company`, sin guardar nada si no existe.
  def self.for(user, company)
    find_by(user_id: user.id, company_id: company.id) || new(user: user, company: company)
  end
end
