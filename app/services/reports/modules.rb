module Reports
  # Qué módulos de la empresa alimentan cada dato de Reportes (spec 033, R2). Una sola fuente para el
  # controlador y los servicios: decide por módulos activos, no por el nombre del plan.
  class Modules
    # Cualquiera de estos crea tickets, que son la base de ingresos y por cobrar.
    INCOME = %i[tickets restaurant work_orders].freeze

    def initialize(company)
      @company = company
    end

    def income? = INCOME.any? { |key| active?(key) }
    def work_orders? = active?(:work_orders)
    def payroll? = active?(:employees)
    def inventory? = active?(:inventory)
    def expenses? = payroll? || inventory?
    def attendance? = payroll? && active?(:attendance)

    private

    def active?(key) = @company.module_active?(key)
  end
end
