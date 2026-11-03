module Reports
  # Qué módulos de la empresa alimentan cada dato de Reportes (spec 033, R2). Una sola fuente para el
  # controlador y los servicios: decide por módulos activos, no por el nombre del plan.
  class Modules
    # Cualquiera de estos crea tickets, que son la base de ingresos y por cobrar. El punto de venta (spec 050) también:
    # una empresa Básico con `pos` ve Ingresos, pero solo con sus ventas.
    INCOME = %i[tickets restaurant work_orders pos].freeze

    def initialize(company)
      @company = company
    end

    def income? = INCOME.any? { |key| active?(key) }
    def work_orders? = active?(:work_orders)
    def pos? = active?(:pos)
    def payroll? = active?(:employees)
    def inventory? = active?(:inventory)
    def expenses? = payroll? || inventory?
    def attendance? = payroll? && active?(:attendance)

    # Los tickets que cuentan como ingreso: solo los de módulos que la empresa tiene activos (spec 050, R8). Las ventas
    # de un módulo apagado o dado de baja se conservan, pero no se consultan hasta que vuelva a estar activo.
    def income_tickets(scope)
      owners = []
      owners << "tickets.work_order_id IS NOT NULL" if work_orders?
      owners << "tickets.check_id IS NOT NULL" if active?(:restaurant)
      owners << "tickets.sale_id IS NOT NULL" if pos?
      owners.empty? ? scope.none : scope.where(owners.join(" OR "))
    end

    private

    def active?(key) = @company.module_active?(key)
  end
end
