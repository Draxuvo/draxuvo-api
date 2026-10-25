module Api
  module V1
    module Restaurant
      # Plano de mesas: estado de cada una, cuentas para llevar y los artículos listos de la persona.
      class TablesController < BaseController
        def index
          tables = current_company.dining_tables.ordered
          open_checks = checks_scope.status_open.includes(:waiter).to_a
          closed_today = closed_today_checks
          return unless stale?(etag: fingerprint(tables, open_checks, closed_today))

          counts = CheckItem.where(check_id: open_checks.map(&:id)).group(:check_id, :status).count
          summaries = open_checks.index_by(&:id).transform_values do |check|
            per_status = counts.select { |(check_id, _), _| check_id == check.id }.transform_keys { |(_, status)| status }
            CheckSerializer.summary(check, restaurant_context, counts: per_status)
          end
          by_table = open_checks.select(&:dining_table_id).index_by(&:dining_table_id)
          by_check = counts.each_with_object(Hash.new { |h, k| h[k] = {} }) { |((check_id, status), n), acc| acc[check_id][status] = n }

          render json: {
            results: tables.map do |t|
              check = by_table[t.id]
              DiningTableSerializer.new(t, summary: check && summaries[check.id],
                                           state: ::Restaurant::TableState.call(check, counts: check && by_check[check.id])).as_json
            end,
            takeouts: open_checks.reject(&:dining_table_id).map { |c| summaries[c.id].merge(takeout_name: c.takeout_name) },
            ready_items: ready_items,
            closed_today: closed_today.map { |c| closed_summary(c) }
          }.merge(stock_alerts_count).merge(overview_for(open_checks, by_check))
        end

        private

        # Cuentas cobradas hoy (spec 038): el plano solo tiene las abiertas y Cuentas lista también las cobradas.
        def closed_today_checks
          checks_scope.status_closed.where(closed_at: Time.zone.now.all_day)
                      .includes(:waiter, :dining_table, :ticket).order(closed_at: :desc).to_a
        end

        # Mesero y total solo para quien es jefe o dueño de la cuenta (spec 032, FR-019b).
        def closed_summary(check)
          own = check.waiter_id == current_user.id
          summary = {
            id: check.id, name: check.dining_table&.name, takeout_name: check.takeout_name,
            closed_at: check.closed_at, ticket_id: check.ticket&.id, mine: own
          }
          return summary unless own || restaurant_context.boss?

          summary.merge(waiter: CheckSerializer.person(check.waiter), total: CheckSerializer.money(check.total))
        end

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

        # Solo para dueño y administrador (spec 032, FR-019b).
        def overview_for(open_checks, by_check)
          return {} unless restaurant_context.boss?

          { overview: ::Restaurant::ServiceOverview.new(current_company, open_checks, by_check).call }
        end

        def stock_alerts_count
          return {} unless restaurant_context.boss?

          { stock_alerts: ::Restaurant::Availability.new(current_company).alerts.size }
        end

        # Cambia cuando cambia cualquier mesa, cuenta abierta o artículo: la consulta sin cambios responde 304.
        def fingerprint(tables, open_checks, closed_today)
          items = CheckItem.where(company_id: current_company.id)
          [ current_user.id, current_role, tables.maximum(:updated_at), open_checks.map { |c| [ c.id, c.updated_at, c.waiter_id ] },
            closed_today.map { |c| [ c.id, c.updated_at ] },
            items.maximum(:updated_at), items.count, current_company.products.maximum(:updated_at) ]
        end
      end
    end
  end
end
