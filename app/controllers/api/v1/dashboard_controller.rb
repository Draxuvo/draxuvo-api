module Api
  module V1
    class DashboardController < BaseController
      def index
        render json: {
          employees:   employees_stats,
          users:       users_stats,
          work_orders: work_orders_stats,
          tickets:     tickets_stats,
          inventory:   inventory_stats,
          attendance:  attendance_stats,
          active_modules: active_modules
        }
      end

      private

      # Las secciones de módulos inactivos conservan su forma pero se calculan sobre un scope vacío,
      # así la UI no cambia y no se exponen datos de un módulo bloqueado (R13, FR-024).
      def active_modules
        @active_modules ||= current_company.active_modules
      end

      def module_scope(module_key, relation)
        active_modules.include?(module_key) ? relation : relation.none
      end

      def employees_stats
        employees = module_scope(:employees, current_company.employees.team)
        counts    = employees.group(:status).count

        {
          total:    employees.count,
          active:   counts["active"].to_i,
          inactive: counts["inactive"].to_i
        }
      end

      def users_stats
        users       = current_company.users
        role_counts = current_company.user_companies.group(:role).count

        {
          total:   users.count,
          by_role: {
            staff:       role_counts["staff"].to_i,
            admin:       role_counts["admin"].to_i,
            owner:       role_counts["owner"].to_i,
            super_admin: 0
          }
        }
      end

      def work_orders_stats
        orders         = module_scope(:work_orders, current_company.work_orders)
        status_counts  = orders.group(:status).count
        priority_counts = orders.group(:priority).count

        {
          total:       orders.count,
          # Por cobrar: órdenes terminadas (done) que aún no se cobran.
          to_charge:       status_counts["done"].to_i,
          to_charge_total: orders.where(status: :done).sum(:total).to_f,
          by_status:   {
            open:        status_counts["open"].to_i,
            in_progress: status_counts["in_progress"].to_i,
            done:        status_counts["done"].to_i,
            paid:        status_counts["paid"].to_i,
            cancelled:   status_counts["cancelled"].to_i
          },
          by_priority: {
            low:    priority_counts["low"].to_i,
            medium: priority_counts["medium"].to_i,
            high:   priority_counts["high"].to_i,
            urgent: priority_counts["urgent"].to_i
          }
        }
      end

      def tickets_stats
        tickets       = module_scope(:tickets, current_company.tickets)
        status_counts = tickets.group(:status).count

        pending_count = status_counts["pending"].to_i
        paid_count    = status_counts["paid"].to_i
        voided_count  = status_counts["voided"].to_i

        total_revenue   = tickets.where(status: :paid).sum(:total)
        pending_revenue = tickets.where(status: :pending).sum(:total)

        {
          total:           tickets.count,
          pending:         pending_count,
          paid:            paid_count,
          voided:          voided_count,
          total_revenue:   total_revenue.to_f,
          pending_revenue: pending_revenue.to_f
        }
      end

      def inventory_stats
        products    = module_scope(:inventory, current_company.products)
        avail_counts = products.group(:available).count

        {
          total:       products.count,
          available:   avail_counts[true].to_i,
          unavailable: avail_counts[false].to_i,
          # Misma regla que GET /products?low_stock=true y ProductSerializer#low_stock (Product.low_stock, spec 016).
          low_stock:   products.low_stock.count,
          out_of_stock: products.counted.where(stock: 0).count,
          by_type:     by_type(products)
        }
      end

      # Productos y valor a costo (solo tipos que se cuentan) por tipo de producto (spec 016, FR-014).
      def by_type(products)
        counts = products.group(:product_type_id).count
        values = products.counted.group(:product_type_id).sum("products.stock * COALESCE(products.unit_cost, 0)")
        current_company.product_types.ordered.select { |type| type.active || counts.key?(type.id) }.map do |type|
          { id: type.id, name: type.name, counted: type.counted, products: counts.fetch(type.id, 0),
            value: type.counted ? values.fetch(type.id, 0).to_f : nil }
        end
      end

      def attendance_stats
        # Rangos de tiempo (no de Date) en Time.zone, así el último día del mes cuenta completo.
        now         = Time.zone.now
        today_range = now.all_day
        month_range = now.all_month

        attendances   = module_scope(:attendance, current_company.attendances.joins(:employee).merge(Employee.team))
        today_records = attendances.where(checkin_at: today_range)
        type_counts   = today_records.group(:attendance_type).count

        {
          today: {
            total:  today_records.count,
            normal: type_counts["normal"].to_i,
            late:   type_counts["late"].to_i,
            absent: type_counts["absent"].to_i
          },
          this_month: attendances.where(checkin_at: month_range).count
        }
      end
    end
  end
end
