module Api
  module V1
    module Restaurant
      # Productos controlados agotados o en su mínimo, para el encargado (FR-042). Es un estado, no un evento.
      class StockAlertsController < BaseController
        before_action :require_boss!

        def index
          availability = ::Restaurant::Availability.new(current_company)
          render json: {
            results: availability.alerts.map do |p|
              { id: p.id, name: p.name, stock: Product.quantity(p.stock), min_stock: Product.quantity(p.min_stock), sold_out: availability.sold_out?(p) }
            end
          }
        end
      end
    end
  end
end
