# Cambia la cantidad de un renglón de una venta abierta; cantidad 0 lo quita (spec 050, FR-013).
module Sales
  class UpdateItem
    include Failures

    def self.call(sale, item_id, quantity) = new(sale, item_id, quantity).call

    def initialize(sale, item_id, quantity)
      @sale = sale
      @item_id = item_id
      @quantity = quantity
    end

    def call
      Sale.transaction do
        @sale.lock!
        ensure_open!(@sale)
        item = @sale.sale_items.find_by(id: @item_id) || not_found!(:item_not_found)
        quantity = decimal(@quantity)
        fail!(:invalid_quantity) if quantity.nil? || quantity.negative?
        quantity.zero? ? item.destroy! : update(item, quantity)
        @sale.recalculate_total!
        @sale
      end
    end

    private

    def update(item, quantity)
      fail!(:invalid_quantity) if item.product && !item.product.fractional? && quantity != quantity.round

      item.update!(quantity: quantity)
    end
  end
end
