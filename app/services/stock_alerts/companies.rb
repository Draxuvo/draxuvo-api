module StockAlerts
  # Empresas a las que se les avisa del stock bajo (spec 045, FR-020 y FR-023): reales (no demo), con el módulo de
  # inventario activo y una suscripción con acceso (no suspendida, cancelada ni vencida).
  module Companies
    module_function

    def each(&block)
      Company.real.includes(:subscription, parent: :subscription).find_each.select { |company| eligible?(company) }.each(&block)
    end

    def eligible?(company)
      company.module_active?(:inventory) && company.billing_subscription&.active_access? == true
    end
  end
end
