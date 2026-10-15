module Reports
  class SummaryService
    def initialize(company, range, period)
      @company = company
      @range   = range
      @period  = period
    end

    def call
      {
        period:      { type: @period, from: @range.first, to: @range.last },
        income:      income_data,
        work_orders: work_orders_data,
        expenses:    expenses_data,
        attendance:  attendance_data
      }
    end

    private

    def income_data
      paid    = @company.tickets.where(status: :paid, paid_at: @range)
      pending = @company.tickets.where(status: :pending, created_at: @range)

      {
        total_revenue:   paid.sum(:total).to_f,
        tickets_paid:    paid.count,
        pending_revenue: pending.sum(:total).to_f,
        tickets_pending: pending.count
      }
    end

    def work_orders_data
      orders        = @company.work_orders.where(created_at: @range)
      status_counts = orders.group(:status).count

      {
        total:        orders.count,
        total_billed: orders.sum(:total).to_f,
        by_status:    {
          open:        status_counts["open"].to_i,
          in_progress: status_counts["in_progress"].to_i,
          done:        status_counts["done"].to_i,
          paid:        status_counts["paid"].to_i,
          cancelled:   status_counts["cancelled"].to_i
        }
      }
    end

    def expenses_data
      payroll_total  = @company.employees.where(status: :active).sum("COALESCE(salary, 0)").to_f
      inventory_cost = @company.stock_movements
                               .where(movement_type: :entry, created_at: @range)
                               .joins(:product)
                               .sum("stock_movements.qty * COALESCE(products.unit_cost, 0)").to_f

      {
        payroll:        payroll_total,
        inventory_cost: inventory_cost,
        total:          payroll_total + inventory_cost
      }
    end

    def attendance_data
      records     = @company.attendances.where(checkin_at: @range)
      type_counts = records.group(:attendance_type).count

      {
        total:  records.count,
        normal: type_counts["normal"].to_i,
        late:   type_counts["late"].to_i,
        absent: type_counts["absent"].to_i
      }
    end
  end
end
