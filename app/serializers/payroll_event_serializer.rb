# Línea de la bitácora de una corrida (spec 037).
class PayrollEventSerializer
  def initialize(event)
    @event = event
  end

  def as_json(*)
    e = @event
    { id: e.id, action: e.action, details: e.details, user: e.user && { id: e.user.id, name: e.user.full_name },
      created_at: e.created_at }
  end
end
