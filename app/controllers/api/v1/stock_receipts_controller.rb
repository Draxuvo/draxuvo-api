module Api
  module V1
    # Recepción de mercancía por lote (spec 034): suma el stock de varios productos de una vez. Seguro ante
    # reintentos con Idempotency-Key.
    class StockReceiptsController < BaseController
      include Idempotent

      requires_module :inventory
      idempotent :create

      def create
        items = Array(params[:items]).map { |item| { product_id: item[:product_id], qty: item[:qty] } }
        movements, products = Stock::Receive.call(company: current_company, user: current_user, items: items, note: params[:note])

        render json: { movements: movements.map { |m| StockMovementSerializer.new(m).as_json },
                       products: products.map { |p| ProductSerializer.new(p).as_json } }, status: :created
      rescue Stock::Receive::Invalid => e
        raise ApiErrors::UnprocessableEntityError.new(
          message: I18n.t("stock.errors.#{e.code}", product: e.product&.name),
          details: { code: e.code.to_s, product: e.product && { id: e.product.id, name: e.product.name } }
        )
      end
    end
  end
end
