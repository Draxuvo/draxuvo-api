module Api
  module V1
    module Restaurant
      # Estaciones del negocio: las ve cualquiera con sesión, las configura el encargado o superior (FR-033).
      class StationsController < BaseController
        before_action :require_boss!, only: %i[create update]

        def index
          render json: { results: current_company.stations.ordered.map { |s| StationSerializer.new(s).as_json } }
        end

        def create
          station = current_company.stations.create!(station_params)
          render json: StationSerializer.new(station).as_json, status: :created
        end

        def update
          station = current_company.stations.find(params[:id])
          station.update!(station_params)
          render json: StationSerializer.new(station).as_json
        end

        private

        def station_params
          params.fetch(:station, params).permit(:name, :is_default, :active, :position)
        end
      end
    end
  end
end
