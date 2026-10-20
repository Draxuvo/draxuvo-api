# Terminal de cobro (spec 015). `payments_count` solo para admin o dueño: decide si se puede borrar.
class PaymentTerminalSerializer
  def initialize(terminal, admin: false)
    @terminal = terminal
    @admin    = admin
  end

  # La terminal dentro de un pago.
  def self.ref(terminal)
    terminal && { id: terminal.id, name: terminal.name, provider: terminal.provider }
  end

  def as_json(*)
    json = self.class.ref(@terminal).merge(provider_label: @terminal.provider_label, active: @terminal.active)
    json[:payments_count] = @terminal.payments_count if @admin
    json
  end
end
