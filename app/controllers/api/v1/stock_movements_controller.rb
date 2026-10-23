# app/controllers/api/v1/stock_movements_controller.rb
module Api
  module V1
    class StockMovementsController < BaseController
      requires_module :inventory

      def index
        movements = current_company.stock_movements
                                   .includes(:product, :user)
                                   .search(params[:search])

        movements = movements.where(product_id: params[:product_id]) if params[:product_id]
        movements = apply_sort(movements, allowed: %i[qty created_at], default: :created_at, default_dir: :desc)
        @pagy, @movements = pagy(movements)
        render json: paginate_response(@pagy, @movements.map { |m| StockMovementSerializer.new(m).as_json })
      end

      def create
        product = current_company.products.find(params[:product_id])

        # Validar stock suficiente en salidas (con decimales en los tipos que los admiten, spec 016)
        if params[:movement_type] == "exit" && product.stock < params[:qty].to_s.to_d.abs
          return render json: { error: I18n.t("products.insufficient_stock", available: Product.quantity(product.stock)) },
                        status: :unprocessable_entity
        end

        movement = product.stock_movements.create!(
          movement_params.merge(company: current_company, user: current_user)
        )

        render json: { movement: StockMovementSerializer.new(movement).as_json,
                       product: ProductSerializer.new(product.reload).as_json }, status: :created
      end

      private

      def movement_params
        params.require(:stock_movement).permit(:movement_type, :qty, :note)
      end
    end
  end
end
