# Cancela una venta ya cobrada (spec 050, FR-030 a FR-033). Bajo bloqueo y en una transacción: anula el ticket y sus
# pagos, regresa al inventario exactamente lo que se descontó al cobrar (`stock_taken`, que puede ser menos de lo
# vendido) y marca la venta cancelada con quién, cuándo y por qué. Repetirla no devuelve nada otra vez.
module Sales
  class Cancel
    include Failures

    def self.call(sale, user, reason) = new(sale, user, reason).call

    def initialize(sale, user, reason)
      @sale = sale
      @user = user
      @company = sale.company
      @reason = reason.to_s.strip
    end

    def call
      Sale.transaction do
        @sale.lock!
        fail!(:not_paid) unless @sale.status_paid?
        fail!(:reason_required) if @reason.empty?

        void_ticket
        return_stock
        @sale.update!(status: :cancelled, cancelled_at: Time.current, cancelled_by: @user, cancel_reason: @reason)
        @sale
      end
    end

    private

    def void_ticket
      ticket = @sale.ticket
      now = Time.current
      ticket.ticket_payments.active.update_all(voided_at: now, updated_at: now)
      ticket.update!(status: :voided, voided_at: now, voided_by: @user, void_reason: @reason)
    end

    # Devuelve lo que de verdad salió. Productos borrados o que ya no se cuentan no se tocan.
    def return_stock
      back = @sale.sale_items.where.not(product_id: nil).where("stock_taken > 0").group_by(&:product_id)
                  .transform_values { |items| items.sum(&:stock_taken) }
      Product.tracked.where(id: back.keys).order(:id).lock.each do |product|
        StockMovement.create!(product: product, company: @company, user: @user, sale: @sale, movement_type: :entry,
                              qty: back.fetch(product.id), note: I18n.t("sale.stock_cancel_note", id: @sale.id))
      end
    end
  end
end
