# Spec 073 (US4): borra de la bitácora de inicios de sesión lo que pasa de 90 días. Corre cada día en el worker
# (config/recurring.yml) y borra por lotes para no bloquear la tabla aunque un ataque la haya llenado.
module LoginAttempts
  class PurgeJob < ApplicationJob
    queue_as :default

    RETENTION = 90.days
    BATCH = 5_000

    def perform(batch_size: BATCH)
      LoginAttempt.where(created_at: ...RETENTION.ago).in_batches(of: batch_size).delete_all
    end
  end
end
