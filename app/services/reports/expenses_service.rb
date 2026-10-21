module Reports
  class ExpensesService
    def initialize(company, range, group_by)
      @company  = company
      @range    = range
      @group_by = group_by
    end

    def call
      payroll   = payroll_data
      inventory = inventory_data

      {
        period:         { from: @range.first, to: @range.last },
        total_expenses: payroll[:total] + inventory[:total],
        payroll:        payroll,
        inventory_cost: inventory
      }
    end

    private

    def payroll_data
      employees = @company.employees.where(status: :active).order(:name)
      total     = employees.sum("COALESCE(salary, 0)").to_f

      {
        total:      total,
        headcount:  employees.count,
        employees:  employees.map do |e|
          {
            id:         e.id,
            name:       e.name,
            position:   e.position,
            department: e.department,
            salary:     e.salary.to_f
          }
        end
      }
    end

    def inventory_data
      movements = @company.stock_movements
                          .where(movement_type: :entry, created_at: @range)
                          .joins(:product)
                          .includes(:product)
                          .order(:created_at)

      total = movements.sum("stock_movements.qty * COALESCE(products.unit_cost, 0)").to_f

      {
        total:      total,
        by_period:  group_movements(movements),
        movements:  movements.map do |m|
          {
            id:           m.id,
            created_at:   m.created_at,
            product_name: m.product.name,
            sku:          m.product.sku,
            qty:          m.qty,
            unit_cost:    m.product.unit_cost.to_f,
            cost:         (m.qty.to_f * m.product.unit_cost.to_f).round(2),
            note:         m.note
          }
        end
      }
    end

    def group_movements(movements)
      movements.group_by { |m| Reports::PeriodKey.call(m.created_at, @group_by) }.map do |period, group|
        cost = group.sum { |m| m.qty.to_f * m.product.unit_cost.to_f }
        {
          period: period,
          cost:   cost.round(2),
          count:  group.size
        }
      end.sort_by { |g| g[:period] }
    end
  end
end
