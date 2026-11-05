# Canal de correo por persona y empresa para los avisos de stock bajo (spec 045). Sin fila valen los valores por omisión
# (correo encendido). `stock_whatsapp` es un valor histórico (spec 048): se conserva en las filas existentes pero ya no
# se lee, no se escribe ni se valida (antes exigía teléfono), para que una preferencia vieja nunca bloquee un guardado.
#
# Spec 057: además guarda un interruptor por tipo de aviso push (todos encendidos por omisión), que se leen y cambian con
# `/push_preference`; `/notification_preference` sigue hablando solo del correo.
class NotificationPreference < ApplicationRecord
  PUSH_KINDS = {
    "check_ready" => :push_check_ready,
    "work_order_assigned" => :push_work_order_assigned,
    "operational_alert" => :push_operational_alerts,
    "low_stock" => :push_low_stock
  }.freeze

  belongs_to :user
  belongs_to :company

  validates :user_id, uniqueness: { scope: :company_id }

  # Preferencia de `user` en `company`, sin guardar nada si no existe.
  def self.for(user, company)
    find_by(user_id: user.id, company_id: company.id) || new(user: user, company: company)
  end

  def push_enabled?(kind) = public_send(PUSH_KINDS.fetch(kind.to_s))
end
