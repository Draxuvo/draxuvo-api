module Api
  module V1
    module Restaurant
      # Plano de mesas: estado de cada una, cuentas para llevar y los artículos listos de la persona.
      class TablesController < BaseController
        def index
          tables = current_company.dining_tables.ordered
          open_checks = checks_scope.status_open.includes(:waiter).to_a
          return unless stale?(etag: fingerprint(tables, open_checks))

          counts = CheckItem.where(check_id: open_checks.map(&:id)).group(:check_id, :status).count
          summaries = open_checks.index_by(&:id).transform_values do |check|
            per_status = counts.select { |(check_id, _), _| check_id == check.id }.transform_keys { |(_, status)| status }
            CheckSerializer.summary(check, restaurant_context, counts: per_status)
          end
          by_table = open_checks.select(&:dining_table_id).index_by(&:dining_table_id)

          render json: {
            results: tables.map { |t| DiningTableSerializer.new(t, summary: by_table[t.id] && summaries[by_table[t.id].id]).as_json },
            takeouts: open_checks.reject(&:dining_table_id).map { |c| summaries[c.id].merge(takeout_name: c.takeout_name) },
            ready_items: ready_items
          }.merge(stock_alerts_count)
        end

        private

        def ready_items
          CheckItem.status_ready.joins(:check)
                   .where(checks: { company_id: current_company.id, status: Check.statuses[:open], waiter_id: current_user.id })
                   .includes(check: :dining_table).order(:ready_at).map do |item|
            {
              id: item.id, name: item.name, quantity: item.quantity, check_id: item.check_id,
              table: item.check.dining_table&.name, takeout_name: item.check.takeout_name, ready_at: item.ready_at
            }
          end
        end

        def stock_alerts_count
          return {} unless restaurant_context.boss?

          { stock_alerts: ::Restaurant::Availability.new(current_company).alerts.size }
        end

        # Cambia cuando cambia cualquier mesa, cuenta abierta o artículo: la consulta sin cambios responde 304.
        def fingerprint(tables, open_checks)
          items = CheckItem.where(company_id: current_company.id)
          [ current_user.id, current_role, tables.maximum(:updated_at), open_checks.map { |c| [ c.id, c.updated_at, c.waiter_id ] },
            items.maximum(:updated_at), items.count, current_company.products.maximum(:updated_at) ]
        end
      end
    end
  end
end
