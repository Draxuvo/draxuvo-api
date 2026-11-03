# Quita un renglón de una venta abierta (spec 050, FR-013).
module Sales
  class RemoveItem
    include Failures

    def self.call(sale, item_id) = new(sale, item_id).call

    def initialize(sale, item_id)
      @sale = sale
      @item_id = item_id
    end

    def call
      Sale.transaction do
        @sale.lock!
        ensure_open!(@sale)
        (@sale.sale_items.find_by(id: @item_id) || not_found!(:item_not_found)).destroy!
        @sale.recalculate_total!
        @sale
      end
    end
  end
end
