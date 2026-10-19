class DiningTableSerializer
  # `summary` es el resumen de la cuenta abierta de la mesa (o nil si está libre).
  def initialize(table, summary: nil)
    @table = table
    @summary = summary
  end

  def as_json(*)
    base = { id: @table.id, name: @table.name, active: @table.active, position: @table.position }
    @summary ? base.merge(check: @summary) : base.merge(check: nil)
  end
end
