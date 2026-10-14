# app/controllers/api/v1/stock_movements_controller.rb
module Api
  module V1
    class StockMovementsController < BaseController
      requires_module :inventory

      def index
        movements = current_company.stock_movements
                                   .includes(:product)
                                   .search(params[:search])

        movements = movements.where(product_id: params[:product_id]) if params[:product_id]
        movements = apply_sort(movements, allowed: %i[qty created_at], default: :created_at, default_dir: :desc)
        @pagy, @movements = pagy(movements)
        render json: paginate_response(@pagy, @movements)
      end

      def create
        product = current_company.products.find(params[:product_id])

        # Validar stock suficiente en salidas
        if params[:movement_type] == "exit" && product.stock < params[:qty].to_i
          return render json: { error: I18n.t("products.insufficient_stock", available: product.stock) },
                        status: :unprocessable_entity
        end

        movement = product.stock_movements.create!(
          movement_params.merge(company: current_company)
        )

        render json: { movement: movement, product: product.reload }, status: :created
      end

      private

      def movement_params
        params.require(:stock_movement).permit(:movement_type, :qty, :note)
      end
    end
  end
end
