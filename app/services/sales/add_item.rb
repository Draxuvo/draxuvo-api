# Agrega un producto a una venta abierta (spec 050, FR-011 a FR-014). Si el producto ya está, suma cantidad y
# conserva el precio con que se agregó. Todo en una transacción con la venta bloqueada.
module Sales
  class AddItem
    include Failures

    def self.call(sale, params) = new(sale, params).call

    def initialize(sale, params)
      @sale = sale
      @company = sale.company
      @params = params.respond_to?(:to_unsafe_h) ? params.to_unsafe_h.with_indifferent_access : params.to_h.with_indifferent_access
    end

    def call
      Sale.transaction do
        @sale.lock!
        ensure_open!(@sale)
        product = find_product
        validate_product!(product)
        quantity = quantity_for(product)
        item = @sale.sale_items.find_by(product_id: product.id)
        item ? add_to(item, product, quantity) : create_item(product, quantity)
        @sale.recalculate_total!
        @sale
      end
    end

    private

    def find_product
      product = if @params[:product_id].present?
        @company.products.find_by(id: @params[:product_id])
      elsif @params[:barcode].present?
        Products::Lookup.call(@company, @params[:barcode])
      elsif @params[:sku].present?
        @company.products.find_by(sku: @params[:sku].to_s.strip)
      end
      product || not_found!(:product_not_found)
    end

    def validate_product!(product)
      fail!(:product_inactive) unless product.available
      fail!(:product_not_sellable) unless product.sellable?
      fail!(:product_without_price) if product.price.nil?
    end

    def quantity_for(product)
      quantity = @params.key?(:quantity) ? decimal(@params[:quantity]) : BigDecimal("1")
      fail!(:invalid_quantity) unless quantity&.positive?
      fail!(:invalid_quantity) if !product.fractional? && quantity != quantity.round

      quantity
    end

    def create_item(product, quantity)
      @sale.sale_items.create!(company: @company, product: product, name: product.name, sku: product.sku,
                               unit_price: product.price, quantity: quantity)
    end

    def add_to(item, product, quantity)
      total = item.quantity + quantity
      fail!(:invalid_quantity) if !product.fractional? && total != total.round

      item.update!(quantity: total)
    end
  end
end
