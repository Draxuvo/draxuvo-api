module Reports
  # Reporte de inventario (spec 033): foto de hoy (existencias, valor, bajo el mínimo) y movimientos del periodo.
  # Solo tipos de producto que se cuentan (spec 016).
  class InventoryService
    LIMIT = 200

    def initialize(company, range)
      @company = company
      @range   = range
    end

    def call
      {
        period:    { from: @range.first, to: @range.last },
        stock:     stock_data,
        movements: movements_data
      }
    end

    # Conteos de la foto de hoy sin armar listas; lo usa el Resumen.
    def stock_summary
      {
        counted_products: counted.count,
        value:            stock_value,
        low_stock_count:  counted.low_stock.count
      }
    end

    private

    def stock_value = counted.sum("products.stock * COALESCE(products.unit_cost, 0)").to_f

    def counted = @company.products.counted

    def stock_data
      {
        counted_products: counted.count,
        value:            stock_value,
        without_cost:     counted.where("products.stock > 0 AND COALESCE(products.unit_cost, 0) = 0").count,
        low_stock:        counted.low_stock.includes(:product_type).order(:stock, :name).limit(LIMIT).map { |p| low_stock_row(p) }
      }
    end

    def low_stock_row(product)
      product_row(product).merge(stock: Product.quantity(product.stock), min_stock: Product.quantity(product.min_stock))
    end

    def movements_data
      sums = @company.stock_movements
                     .where(created_at: @range)
                     .joins(product: :product_type).where(product_types: { counted: true })
                     .group(:product_id)
                     .pluck(:product_id,
                            Arel.sql("SUM(CASE WHEN stock_movements.movement_type = 0 THEN ABS(stock_movements.qty) ELSE 0 END)"),
                            Arel.sql("SUM(CASE WHEN stock_movements.movement_type = 1 THEN ABS(stock_movements.qty) ELSE 0 END)"),
                            Arel.sql("SUM(CASE WHEN stock_movements.movement_type = 2 THEN stock_movements.qty ELSE 0 END)"))
      sums = sums.sort_by { |_, entries, exits, adjustments| -(entries + exits + adjustments.abs) }
      products = @company.products.includes(:product_type).where(id: sums.first(LIMIT).map(&:first)).index_by(&:id)

      {
        truncated: sums.size > LIMIT,
        rows:      sums.first(LIMIT).map do |id, entries, exits, adjustments|
          product_row(products[id]).merge(entries: Product.quantity(entries), exits: Product.quantity(exits),
                                          adjustments: Product.quantity(adjustments))
        end
      }
    end

    def product_row(product)
      unit = product.unit
      { id: product.id, name: product.name, sku: product.sku, unit: unit&.key }
    end
  end
end
