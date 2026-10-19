module Api
  module V1
    module Restaurant
      # Cancela un artículo ya mandado. Las reglas de quién puede viven en Restaurant::CancelItem.
      class ItemCancellationsController < BaseController
        def create
          check = find_check(params[:check_id])
          item = check.check_items.find(params[:id])
          ::Restaurant::CancelItem.call(item, restaurant_context, params[:reason])
          render json: serialize_check(check.reload)
        end
      end
    end
  end
end
