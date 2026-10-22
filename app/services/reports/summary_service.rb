module Reports
  class SummaryService
    def initialize(company, range, period, compare: false)
      @company = company
      @range   = range
      @period  = period
      @compare = compare
      @modules = Modules.new(company)
    end

    # Cada bloque sale solo si su módulo está activo (spec 033, FR-007): no se devuelven en cero.
    def call
      result = { period: { type: @period, from: @range.first, to: @range.last } }
      result[:income]      = income_data if @modules.income?
      result[:work_orders] = work_orders_data if @modules.work_orders?
      result[:expenses]    = expenses_data if @modules.expenses?
      result[:attendance]  = attendance_data if @modules.attendance?
      result[:inventory]   = inventory_data if @modules.inventory?
      result[:previous]    = previous_data if @compare
      result
    end

    private

    # Mismo cálculo de ingresos y gastos sobre el periodo anterior de igual duración.
    def previous_data
      range = Comparison.previous_range(@range)
      result = { period: { from: range.first, to: range.last } }
      result[:income] = income_data(range).slice(:total_revenue, :pending_revenue) if @modules.income?
      result[:expenses] = expenses_data(range) if @modules.expenses?
      result
    end

    # Foto de hoy, igual que el reporte de inventario (no depende del periodo).
    def inventory_data
      stock = InventoryService.new(@company, @range).stock_summary
      { value: stock[:value], counted_products: stock[:counted_products], low_stock: stock[:low_stock_count] }
    end

    def income_data(range = @range)
      paid    = @company.tickets.where(status: :paid, paid_at: range)
      pending = @company.tickets.where(status: :pending, created_at: range)

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

    def expenses_data(range = @range)
      payroll_total  = @modules.payroll? ? @company.employees.where(status: :active).sum("COALESCE(salary, 0)").to_f : 0.0
      inventory_cost = if @modules.inventory?
        @company.stock_movements
                .where(movement_type: :entry, created_at: range)
                .joins(:product)
                .sum("stock_movements.qty * COALESCE(products.unit_cost, 0)").to_f
      else
        0.0
      end

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
