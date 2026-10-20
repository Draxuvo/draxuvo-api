module Api
  module V1
    module Restaurant
      # Armar la cuenta: agregar, ajustar y quitar artículos que aún no se mandan (FR-006, FR-029).
      class CheckItemsController < BaseController
        before_action :set_check

        def create
          # Solo productos de tipos que se venden (spec 016); un insumo responde 404 como uno no disponible.
          product = current_company.products.available.sellable.find(params[:product_id])
          quantity = params[:quantity].to_i
          quantity = 1 if quantity < 1
          availability = ::Restaurant::Availability.new(current_company)
          available = availability.available_qty(product)
          invalid!(:sold_out, name: product.name) if available && quantity > available

          @check.check_items.create!(company: current_company, product: product, name: product.name,
                                     unit_price: product.price || 0, quantity: quantity, note: note_param)
          render json: serialize_check(@check.reload), status: :created
        end

        def update
          item = draft_item
          attrs = {}
          attrs[:quantity] = params[:quantity].to_i if params.key?(:quantity)
          attrs[:note] = note_param if params.key?(:note)
          item.update!(attrs)
          render json: serialize_check(@check.reload)
        end

        def destroy
          draft_item.destroy!
          render json: serialize_check(@check.reload)
        end

        private

        def set_check
          @check = find_check(params[:check_id])
          invalid!(:check_not_open) unless @check.status_open?
        end

        def draft_item
          item = @check.check_items.find(params[:id])
          invalid!(:not_draft) unless item.status_draft?
          item
        end

        def note_param = params[:note].to_s.strip.presence
      end
    end
  end
end
