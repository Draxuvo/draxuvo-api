# Terminal de cobro (spec 015). `payments_count` solo para admin o dueño: decide si se puede borrar.
# Spec 069: `kind` (manual o integrada), `chargeable` (se le pueden mandar cobros) y el estado de su conexión; el
# dispositivo solo para admin o dueño.
class PaymentTerminalSerializer
  def initialize(terminal, admin: false, restart_required: nil)
    @terminal = terminal
    @admin    = admin
    @restart_required = restart_required
  end

  # La terminal dentro de un pago.
  def self.ref(terminal)
    terminal && { id: terminal.id, name: terminal.name, provider: terminal.provider }
  end

  def as_json(*)
    json = self.class.ref(@terminal).merge(provider_label: @terminal.provider_label, active: @terminal.active,
                                           kind: @terminal.kind, chargeable: @terminal.chargeable?,
                                           connection_status: @terminal.terminal_connection&.status)
    if @admin
      json[:payments_count] = @terminal.payments_count
      json[:device_id] = @terminal.device_id
      json[:device_mode] = @terminal.device_mode
    end
    json[:restart_required] = @restart_required unless @restart_required.nil?
    json
  end
end
