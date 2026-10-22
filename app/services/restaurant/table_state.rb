module Restaurant
  # Estado de una mesa, derivado de su cuenta abierta (spec 032): `free`, `occupied` o `to_pay`.
  # Por cobrar = sin artículos por preparar o entregar, con al menos uno entregado y saldo pendiente.
  module TableState
    module_function

    def call(check, counts: nil)
      return "free" unless check&.status_open?

      counts ||= check.check_items.group(:status).count
      pending = %w[new preparing ready].sum { |status| counts.fetch(status, 0) }
      delivered = counts.fetch("delivered", 0)
      pending.zero? && delivered.positive? && check.balance.positive? ? "to_pay" : "occupied"
    end
  end
end
