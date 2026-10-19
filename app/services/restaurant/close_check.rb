# Cierra una cuenta cobrada (o sin saldo, con motivo): crea el ticket, descuenta el inventario controlado
# y libera la mesa (FR-024, FR-026, FR-028). Se llama dentro de la transacción que ya tiene bloqueada la cuenta.
module Restaurant
  class CloseCheck
    Result = Struct.new(:ticket, :shortages, keyword_init: true)

    def self.call(check, user, reason: nil) = new(check, user, reason).call

    def initialize(check, user, reason)
      @check = check
      @user = user
      @reason = reason
    end

    def call
      ticket = create_ticket
      shortages = deduct_stock
      @check.update!(status: :closed, closed_at: Time.current)
      Result.new(ticket: ticket, shortages: shortages)
    end

    private

    def create_ticket
      payments = @check.check_payments.order(:id).to_a
      received = payments.sum { |p| p.amount_received || p.amount }
      change = payments.sum { |p| p.change_given || 0 }
      Ticket.create!(
        check: @check, company: @check.company, status: :paid, total: @check.total, paid_at: Time.current,
        payment_method: payment_method(payments), amount_received: received, change_given: change, charged_by: @user,
        notes: @reason
      )
    end

    # Un solo método, o mixto; una cuenta en cero (cortesía) se registra como efectivo por 0.
    def payment_method(payments)
      methods = payments.map(&:payment_method).uniq
      return :cash if methods.empty?

      methods.one? ? methods.first : :mixed
    end

    # Descuenta lo vendido de los productos que controlan inventario. Si no alcanza, el inventario queda en
    # cero (nunca negativo) y la falta se devuelve para que el encargado la vea en las alertas.
    def deduct_stock
      sold = @check.check_items.counted.where.not(product_id: nil).group(:product_id).sum(:quantity)
      shortages = []
      Product.tracked.where(id: sold.keys).order(:id).lock.each do |product|
        wanted = sold.fetch(product.id)
        taken = [ wanted, product.stock.to_i ].min
        shortages << { product_id: product.id, missing: wanted - taken } if taken < wanted
        next unless taken.positive?

        StockMovement.create!(product: product, company: @check.company, movement_type: :exit, qty: taken,
                              note: I18n.t("restaurant.stock_note", id: @check.id))
      end
      shortages
    end
  end
end
