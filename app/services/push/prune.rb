module Push
  # Limpieza diaria (spec 057, FR-004 y data-model): desactiva los teléfonos que llevan 30 días sin abrir la app con
  # sesión y borra la bitácora de más de 90 días.
  module Prune
    module_function

    def call(now: Time.current)
      stale = PushDevice.active.where(last_seen_at: ...(now - PushDevice::STALE_AFTER))
      stale.update_all(disabled_at: now, disabled_reason: "stale", updated_at: now)
      PushDelivery.where(created_at: ...(now - PushDelivery::RETENTION)).delete_all
    end
  end
end
