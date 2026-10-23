module Stock
  # Confirma un conteo físico (spec 034): un ajuste por cada producto cuya cantidad contada difiere del stock
  # ACTUAL, sin tocar lo no contado. Confirmar de nuevo un conteo ya confirmado devuelve el mismo resultado.
  class ConfirmCount
    class Invalid < StandardError
      attr_reader :code, :product

      def initialize(code, product = nil)
        @code = code
        @product = product
        super(code.to_s)
      end
    end

    Result = Struct.new(:count, :adjustments, :changed_since_baseline, keyword_init: true)

    def self.call(**args) = new(**args).call

    def initialize(count:, user:)
      @count = count
      @user = user
    end

    def call
      StockCount.transaction do
        @count.lock!
        return replay if @count.confirmed?
        raise Invalid.new(:count_closed) unless @count.draft?

        items = @count.items.includes(:product).to_a
        # Se bloquean los productos para que ningún movimiento cambie el stock entre leerlo y ajustarlo.
        products = @count.company.products.where(id: items.map(&:product_id)).order(:id).lock.index_by(&:id)
        entries = items.filter_map do |item|
          delta = item.counted_qty.to_d - products.fetch(item.product_id).stock.to_d
          { product: products.fetch(item.product_id), delta: delta, type: :adjustment, note: I18n.t("stock.count.note", id: @count.id) } unless delta.zero?
        end
        changed = items.select { |item| products.fetch(item.product_id).stock.to_d != item.baseline_stock.to_d }.map(&:product_id)

        movements = RecordMovements.call(company: @count.company, user: @user, entries: entries)
        @count.update!(status: :confirmed, confirmed_at: Time.current, confirmed_by: @user,
                       result: { "adjustments" => movements.map(&:id), "changed_since_baseline" => changed })
        Result.new(count: @count, adjustments: movements, changed_since_baseline: changed)
      end
    rescue RecordMovements::Invalid => e
      raise Invalid.new(e.code, e.product)
    end

    private

    def replay
      ids = @count.result["adjustments"] || []
      Result.new(count: @count, adjustments: StockMovement.where(id: ids).includes(:user).order(:id).to_a,
                 changed_since_baseline: @count.result["changed_since_baseline"] || [])
    end
  end
end
