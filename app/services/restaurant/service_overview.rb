module Restaurant
  # Resumen vivo del servicio para dueño, administrador y gerente (spec 032): cuentas abiertas, saldo por cobrar,
  # comandas pendientes y la cuenta abierta más antigua.
  class ServiceOverview
    def initialize(company, open_checks, counts_by_check)
      @company = company
      @open_checks = open_checks
      @counts = counts_by_check
    end

    def call
      to_pay = @open_checks.select { |check| TableState.call(check, counts: @counts[check.id] || {}) == "to_pay" }
      pending = @open_checks.sum { |check| @counts.fetch(check.id, {}).values_at("new", "preparing").compact.sum }
      oldest = @open_checks.map(&:opened_at).compact.min
      {
        open_checks: @open_checks.size,
        to_pay_total: format("%.2f", to_pay.sum(&:balance)),
        pending_comandas: pending,
        oldest_open_minutes: oldest && ((Time.current - oldest) / 60).floor
      }
    end
  end
end
