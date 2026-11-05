module Push
  # Limpieza diaria de teléfonos sin uso y bitácora vieja (spec 057, `config/recurring.yml`).
  class PruneDevicesJob < ApplicationJob
    queue_as :default

    def perform = Prune.call
  end
end
