# Existencias que quedan para vender (research R3): inventario menos lo ya comprometido en cuentas abiertas.
# Solo cuentan los productos que controlan inventario.
module Restaurant
  class Availability
    def initialize(company)
      @company = company
    end

    # { product_id => unidades en cuentas abiertas que aún no descuentan inventario }
    def committed
      @committed ||= CheckItem.counted
                              .joins(:check)
                              .where(checks: { company_id: @company.id, status: Check.statuses[:open] })
                              .where.not(product_id: nil)
                              .group(:product_id).sum(:quantity)
    end

    def available_qty(product)
      return nil unless product.tracks_stock?

      product.stock.to_i - committed.fetch(product.id, 0)
    end

    def sold_out?(product)
      qty = available_qty(product)
      !qty.nil? && qty <= 0
    end

    # Misma regla que Product.low_stock (spec 016): tipo que se cuenta, mínimo mayor que cero.
    def low?(product)
      product.low_stock?
    end

    # Productos controlados agotados o en su mínimo (alertas del encargado, FR-042).
    def alerts
      @company.products.tracked.includes(:product_type).order(:name).select { |p| sold_out?(p) || low?(p) }
    end
  end
end
