class DiningTableSerializer
  # `summary` es el resumen de la cuenta abierta de la mesa (o nil si está libre).
  # `state` (free, occupied, to_pay) lo calcula el plano con las cuentas ya cargadas.
  def initialize(table, summary: nil, state: nil)
    @table = table
    @summary = summary
    @state = state
  end

  def as_json(*)
    base = { id: @table.id, name: @table.name, active: @table.active, position: @table.position }
    base[:state] = @state if @state
    @summary ? base.merge(check: @summary) : base.merge(check: nil)
  end
end
