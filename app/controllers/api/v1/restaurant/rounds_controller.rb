module Api
  module V1
    module Restaurant
      # Manda a las estaciones lo que está sin mandar. Seguro ante reintentos con Idempotency-Key (FR-010).
      class RoundsController < BaseController
        idempotent :create

        def create
          result = ::Restaurant::SendRound.call(find_check, restaurant_context)
          check = find_check
          render json: {
            kitchen_order: result.kitchen_order && { id: result.kitchen_order.id, number: result.kitchen_order.number,
                                                     sent_at: result.kitchen_order.sent_at },
            sent: result.sent.map { |i| { id: i.id, name: i.name, quantity: i.quantity, station: i.station && { id: i.station.id, name: i.station.name } } },
            rejected: result.rejected.map { |i, qty| { id: i.id, name: i.name, reason: "sold_out", available_qty: qty } },
            check: serialize_check(check)
          }, status: result.kitchen_order ? :created : :ok
        end
      end
    end
  end
end
