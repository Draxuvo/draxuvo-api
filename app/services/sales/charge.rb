# Cobra una venta abierta y emite su ticket (spec 050, FR-020 a FR-028). Todo o nada, en una transacción con la
# venta bloqueada: crea el ticket pagado, sus pagos y los movimientos de stock. El reparto de pagos (efectivo, tarjeta,
# transferencia y mixto) es el mismo del cobro de órdenes de trabajo. El inventario nunca queda negativo: se descuenta
# hasta cero y lo que faltó se devuelve en `shortages` para avisar al cajero.
module Sales
  class Charge
    include Failures

    Result = Struct.new(:sale, :ticket, :shortages, keyword_init: true)

    def self.call(sale, user, params) = new(sale, user, params).call

    def initialize(sale, user, params)
      @sale = sale
      @user = user
      @company = sale.company
      @params = params.respond_to?(:to_unsafe_h) ? params.to_unsafe_h.with_indifferent_access : params.to_h.with_indifferent_access
    end

    def call
      Sale.transaction do
        expected = @params[:lock_version]
        @sale.lock!
        ensure_open!(@sale)
        ensure_fresh!(expected)
        @sale.recalculate_total!
        fail!(:empty) if @sale.sale_items.none? || !@sale.total.positive?

        split = WorkOrders::ChargePayments.call(@company, @sale.total, @params)
        ticket = create_ticket(split)
        shortages = deduct_stock
        @sale.update!(status: :paid, paid_at: Time.current, charged_by: @user)
        Result.new(sale: @sale, ticket: ticket, shortages: shortages)
      end
    end

    private

    # La venta cambió desde que se mostró al cajero (otra pestaña, otro equipo): que la revise antes de cobrar.
    def ensure_fresh!(expected)
      return if expected.present? && expected.to_i == @sale.lock_version

      fail!(:stale_object, status: :conflict)
    end

    def create_ticket(split)
      ticket = Ticket.create!(
        sale: @sale, company: @company, status: :paid, total: @sale.total, payment_method: split.payment_method,
        amount_received: split.amount_received, change_given: split.change_given, charged_by: @user, paid_at: Time.current
      )
      split.payments.each do |attrs|
        ticket.ticket_payments.create!(attrs.merge(company: @company, created_by: @user))
      end
      ticket
    end

    # Descuenta lo vendido de los productos que se cuentan, bloqueándolos por id (dos cajeros no se cruzan).
    # Guarda en cada renglón lo que de verdad se descontó, para devolverlo exacto si se cancela.
    def deduct_stock
      items = @sale.sale_items.where.not(product_id: nil).to_a
      wanted = items.group_by(&:product_id).transform_values { |rows| rows.sum(&:quantity) }
      shortages = []
      Product.tracked.where(id: wanted.keys).order(:id).lock.each do |product|
        quantity = wanted.fetch(product.id)
        taken = [ quantity, product.stock.to_d ].min
        shortages << { product_id: product.id, name: product.name, missing: Product.quantity(quantity - taken) } if taken < quantity
        record_taken(items.select { |item| item.product_id == product.id }, taken)
        next unless taken.positive?

        StockMovement.create!(product: product, company: @company, user: @user, sale: @sale, movement_type: :exit,
                              qty: taken, note: I18n.t("sale.stock_note", id: @sale.id))
      end
      shortages
    end

    def record_taken(items, taken)
      items.each do |item|
        part = [ item.quantity, taken ].min
        item.update_columns(stock_taken: part, updated_at: Time.current)
        taken -= part
      end
    end
  end
end
