module Stock
  # Recepción de mercancía (spec 034): entradas de varios productos en una sola transacción, todo o nada.
  class Receive
    class Invalid < StandardError
      attr_reader :code, :product

      def initialize(code, product = nil)
        @code = code
        @product = product
        super(code.to_s)
      end
    end

    def self.call(**args) = new(**args).call

    # `items`: [{ product_id:, qty: }]; un mismo producto repetido suma sus cantidades.
    def initialize(company:, user:, items:, note: nil)
      @company = company
      @user = user
      @items = items
      @note = note.presence || I18n.t("stock.receive.note")
    end

    def call
      raise Invalid.new(:empty_items) if @items.blank?

      quantities = Hash.new(0.to_d)
      @items.each do |item|
        qty = parse_qty(item[:qty])
        raise Invalid.new(:invalid_qty) unless qty&.positive?

        quantities[item[:product_id].to_i] += qty
      end

      products = @company.products.includes(:product_type).where(id: quantities.keys).index_by(&:id)
      missing = quantities.keys - products.keys
      raise ActiveRecord::RecordNotFound, "Product #{missing.first}" if missing.any?

      entries = quantities.map { |id, qty| { product: products.fetch(id), delta: qty, type: :entry, note: @note } }
      movements = RecordMovements.call(company: @company, user: @user, entries: entries)
      [ movements, products.values.each(&:reload) ]
    rescue RecordMovements::Invalid => e
      raise Invalid.new(e.code == :not_counted ? :not_counted : :invalid_qty, e.product)
    end

    private

    def parse_qty(value)
      BigDecimal(value.to_s)
    rescue ArgumentError, TypeError
      nil
    end
  end
end
