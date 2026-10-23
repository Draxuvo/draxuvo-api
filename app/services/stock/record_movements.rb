module Stock
  # Registra movimientos de stock en bloque y actualiza el stock de cada producto en una sola pasada (spec 034).
  # `entries`: [{ product:, delta:, type: :entry|:exit|:adjustment, note: }]; `delta` va con signo
  # (positivo suma, negativo resta). Todo o nada.
  class RecordMovements
    class Invalid < StandardError
      attr_reader :product, :code

      def initialize(code, product)
        @code = code
        @product = product
        super("#{code}: #{product.name}")
      end
    end

    TYPES = { entry: 0, exit: 1, adjustment: 2 }.freeze

    def self.call(**args) = new(**args).call

    def initialize(company:, user:, entries:)
      @company = company
      @user = user
      @entries = entries.reject { |entry| entry[:delta].to_d.zero? }
    end

    def call
      return [] if @entries.empty?

      now = Time.current
      Product.transaction do
        deltas = Hash.new(0.to_d)
        rows = @entries.map do |entry|
          product = entry.fetch(:product)
          delta = entry.fetch(:delta).to_d
          validate!(product, delta)
          deltas[product.id] += delta
          { product_id: product.id, company_id: @company.id, user_id: @user&.id, movement_type: TYPES.fetch(entry.fetch(:type)),
            qty: entry[:type] == :adjustment ? delta : delta.abs, note: entry[:note], created_at: now, updated_at: now }
        end
        ensure_non_negative!(deltas)
        ids = StockMovement.insert_all!(rows, returning: %w[id]).rows.flatten
        values = deltas.map { |product_id, delta| Product.sanitize_sql_array([ "(?::bigint, ?::numeric)", product_id, delta ]) }.join(", ")
        Product.connection.execute(
          Product.sanitize_sql_array([ "UPDATE products SET stock = products.stock + v.delta, updated_at = ? FROM (VALUES #{values}) AS v(id, delta) WHERE products.id = v.id", now ])
        )
        StockMovement.where(id: ids).includes(:user).order(:id).to_a
      end
    end

    private

    def validate!(product, delta)
      raise Invalid.new(:not_counted, product) unless product.counted?
      raise Invalid.new(:integer_only, product) if !product.fractional? && delta != delta.round
    end

    def ensure_non_negative!(deltas)
      products = Product.where(id: deltas.keys).index_by(&:id)
      deltas.each do |product_id, delta|
        product = products.fetch(product_id)
        raise Invalid.new(:insufficient_stock, product) if product.stock.to_d + delta < 0
      end
    end
  end
end
