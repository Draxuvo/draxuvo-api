module Api
  module V1
    module Restaurant
      # "Marcar todo": avanza todos los artículos de una comanda en la estación.
      class StationOrdersController < BaseController
        def advance
          station = current_company.stations.find(params[:station_id])
          items = ::Restaurant::AdvanceItems.order(station, params[:id])
          render json: { results: items.map { |i| { id: i.id, status: i.status } } }
        end
      end
    end
  end
end
