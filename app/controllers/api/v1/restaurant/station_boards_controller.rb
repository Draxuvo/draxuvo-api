module Api
  module V1
    module Restaurant
      # Lo pendiente de una estación, por comanda y por orden de llegada (FR-012, FR-013, FR-017).
      class StationBoardsController < BaseController
        CANCELLED_VISIBLE_FOR = 2.minutes

        def show
          station = current_company.stations.find(params[:station_id])
          items = board_items(station)
          return unless stale?(etag: [ station.id, items.map { |i| [ i.id, i.status, i.updated_at ] }, Time.current.to_i / 30 ])

          render json: {
            station: { id: station.id, name: station.name, kind: station.kind },
            server_time: Time.current,
            orders: items.group_by(&:kitchen_order).sort_by { |order, _| order.sent_at }.map { |order, list| order_json(order, list) }
          }
        end

        private

        def board_items(station)
          scope = station.check_items.joins(:check).where(checks: { status: Check.statuses[:open] })
          pending = scope.where(status: %i[new preparing])
          recently_cancelled = scope.where(status: :cancelled).where(cancelled_at: CANCELLED_VISIBLE_FOR.ago..)
          pending.or(recently_cancelled).where.not(kitchen_order_id: nil)
                 .includes(kitchen_order: { check: %i[dining_table waiter] }).order(:id).to_a
        end

        def order_json(order, items)
          check = order.check
          {
            id: order.id, number: order.number, sent_at: order.sent_at,
            table: check.dining_table&.name, takeout_name: check.takeout_name, waiter: check.waiter.full_name,
            items: items.map { |i| { id: i.id, name: i.name, quantity: i.quantity, note: i.note, status: i.status } }
          }
        end
      end
    end
  end
end
