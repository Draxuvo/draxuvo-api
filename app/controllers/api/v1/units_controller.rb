# app/controllers/api/v1/units_controller.rb
module Api
  module V1
    class UnitsController < BaseController
      requires_module :inventory

      def index
        units = Unit.ordered
        units = units.where(group: params[:group]) if params[:group].present?

        grouped = units.group_by(&:group).transform_values do |items|
          items.map { |u| UnitSerializer.new(u).as_json }
        end

        render json: { units: grouped }
      end
    end
  end
end
