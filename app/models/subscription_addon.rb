# Un módulo extra contratado sobre el plan de una suscripción (spec 050). Con `ends_at` vacío está activo; tras una
# baja, `ends_at` es el fin del periodo ya pagado y el módulo sigue activo hasta esa fecha. Reactivar reutiliza la fila.
class SubscriptionAddon < ApplicationRecord
  belongs_to :subscription
  belongs_to :company

  validates :module, inclusion: { in: ->(_) { Addon::KEYS.map(&:to_s) } },
                     uniqueness: { scope: :subscription_id }
  validates :amount_cents, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :started_at, presence: true

  # Vigentes: sin baja o con baja cuyo fin de acceso aún no llega.
  scope :current, -> { where("subscription_addons.ends_at IS NULL OR subscription_addons.ends_at > ?", Time.current) }

  def current? = ends_at.nil? || ends_at.future?

  def ending? = ends_at.present? && ends_at.future?

  def status = ending? ? "ending" : "active"

  def addon = Addon.find(self.module)
end
