module TerminalCharges
  # Barrido cada minuto (spec 069, research R5): el respaldo de los avisos del proveedor. Consulta las abiertas que llevan
  # 30 s sin consultarse y las que terminaron sin cobro en Draxuvo durante 15 min (aprobaciones tardías). Una solicitud
  # que nunca llegó al proveedor (sin id de orden) no puede quedar ocupando la terminal: pasa a rechazada.
  class SweepJob < ApplicationJob
    queue_as :default

    def perform
      TerminalCharge.open.where(provider_order_id: nil).where(created_at: ...1.minute.ago).find_each do |charge|
        charge.update!(status: "declined", status_detail: "provider_unavailable", resolved_at: Time.current)
        TerminalEvent.log!(:charge_declined, charge: charge, reason: "provider_unavailable")
      end
      TerminalCharge.due_for_sync.find_each { |charge| SyncJob.perform_later(charge.id) }
    end
  end
end
