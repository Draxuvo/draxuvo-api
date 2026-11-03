module Reports
  # Ventas de mostrador cobradas en el periodo (spec 050, FR-051): totales, por producto y por cajero. Las ventas
  # canceladas no cuentan. Solo existe con el módulo `pos`.
  class SalesService
    def initialize(company, range)
      @company = company
      @range = range
    end

    def call
      totals.merge(period: { from: @range.first, to: @range.last }, by_product: by_product, by_cashier: by_cashier)
    end

    # Cifras del Resumen: ingresos de ventas, cuántas fueron y cuántas unidades salieron.
    def totals
      {
        total_revenue: sales.sum(:total).to_f,
        total_sales: sales.count,
        units: Product.quantity(items.sum(:quantity)) || 0
      }
    end

    private

    def sales = @sales ||= @company.sales.where(status: :paid, paid_at: @range)

    def items = SaleItem.where(sale_id: sales.select(:id))

    # Un renglón por producto (el nombre y la clave de la venta más reciente); los productos que ya no existen se agrupan por nombre.
    def by_product
      key = "COALESCE(sale_items.product_id::text, 'n:' || sale_items.name)"
      rows = items.group(Arel.sql(key)).pluck(
        Arel.sql("MIN(sale_items.product_id)"), Arel.sql("MAX(sale_items.name)"), Arel.sql("MAX(sale_items.sku)"),
        Arel.sql("SUM(sale_items.quantity)"), Arel.sql("SUM(sale_items.subtotal)")
      )
      rows.map do |product_id, name, sku, units, revenue|
        { product_id: product_id, name: name, sku: sku, units: Product.quantity(units), revenue: revenue.to_f }
      end.sort_by { |row| [ -row[:revenue], row[:name].to_s ] }
    end

    def by_cashier
      names = User.where(id: sales.select(:charged_by_id)).index_by(&:id)
      sales.group(:charged_by_id).pluck(:charged_by_id, Arel.sql("COUNT(*)"), Arel.sql("SUM(sales.total)")).map do |user_id, count, revenue|
        { user_id: user_id, name: names[user_id]&.full_name, sales: count, revenue: revenue.to_f }
      end.sort_by { |row| -row[:revenue] }
    end
  end
end
