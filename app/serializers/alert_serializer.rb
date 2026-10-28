# Una alerta activa con las claves de specs/045-alertas-operativas/contracts/api.md.
class AlertSerializer
  def initialize(alert, snooze: nil)
    @alert = alert
    @snooze = snooze
  end

  def as_json(*)
    json = {
      id: @alert.id, kind: @alert.kind, severity: @alert.severity,
      minutes: @alert.minutes, threshold_minutes: @alert.threshold_minutes,
      subject: @alert.subject, owner: @alert.owner,
      total: @alert.total, stock: @alert.stock, min_stock: @alert.min_stock
    }
    json.merge!(snoozed_until: @snooze.snoozed_until, snoozed_by: @snooze.user&.full_name) if @snooze
    json
  end
end
