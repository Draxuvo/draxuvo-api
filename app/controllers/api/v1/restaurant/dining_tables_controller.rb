module Api
  module V1
    module Restaurant
      # Alta y cambio de mesas (FR-033). El plano con su estado lo da TablesController.
      class DiningTablesController < BaseController
        before_action :require_boss!

        def create
          table = current_company.dining_tables.create!(table_params)
          render json: DiningTableSerializer.new(table).as_json, status: :created
        end

        def update
          table = current_company.dining_tables.find(params[:id])
          table.update!(table_params)
          render json: DiningTableSerializer.new(table).as_json
        end

        private

        def table_params
          params.fetch(:table, params).permit(:name, :active, :position)
        end
      end
    end
  end
end
