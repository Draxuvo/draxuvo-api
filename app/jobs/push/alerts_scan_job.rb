module Push
  # Revisión de alertas operativas para push (spec 057, US4): cada minuto (`config/recurring.yml`).
  class AlertsScanJob < ApplicationJob
    queue_as :default

    def perform = AlertsScan.call
  end
end
