module Api
  module V1
    module Restaurant
      # Cualquier persona de la empresa con sesión puede avanzar lo de una estación (FR-037).
      class StationItemsController < BaseController
        def advance
          station = current_company.stations.find(params[:station_id])
          item, = ::Restaurant::AdvanceItems.item(station, params[:id])
          render json: { id: item.id, status: item.status }
        end
      end
    end
  end
end
