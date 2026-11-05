module Api
  module V1
    module Restaurant
      # "Marcar todo": avanza todos los artículos de una comanda en la estación.
      class StationOrdersController < BaseController
        def advance
          station = current_company.stations.find(params[:station_id])
          items = ::Restaurant::AdvanceItems.order(station, params[:id])
          # Spec 057: avisa al mesero cuando su comanda queda lista (ya fuera de la transacción).
          ::Push::CheckReadyJob.enqueue_for(items.select(&:status_ready?).map(&:kitchen_order_id), current_user.id)
          render json: { results: items.map { |i| { id: i.id, status: i.status } } }
        end
      end
    end
  end
end
