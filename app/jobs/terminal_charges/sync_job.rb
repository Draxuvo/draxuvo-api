module TerminalCharges
  # Consulta al proveedor una solicitud y la resuelve (spec 069, research R4 y R5). Lo encolan el aviso del proveedor, la
  # pantalla que espera y el barrido. Ante un proveedor caído se reintenta con espera.
  class SyncJob < ApplicationJob
    queue_as :default

    retry_on TerminalProviders::Error, wait: 10.seconds, attempts: 5

    def perform(charge_id)
      charge = TerminalCharge.find_by(id: charge_id)
      Sync.call(charge) if charge
    end
  end
end
