# Descuenta del inventario lo vendido en una orden de trabajo al cobrarla (spec 054, H-49). Calcado de
# `Sales::Charge#deduct_stock`: el inventario nunca queda negativo (se descuenta hasta cero y lo que faltó se devuelve en
# `shortages`) y cada renglón guarda lo que de verdad salió (`stock_taken`) para devolver exactamente eso al anular.
# Debe llamarse dentro de la transacción del cobro, con la orden bloqueada.
module WorkOrders
  class DeductStock
    def self.call(order, user) = new(order, user).call

    def initialize(order, user)
      @order = order
      @user = user
      @company = order.company
    end

    # Devuelve [{ product_id:, name:, missing: }] con lo que no alcanzó; [] si todo salió.
    def call
      items = @order.work_order_items.where.not(product_id: nil).to_a
      wanted = items.group_by(&:product_id).transform_values { |rows| rows.sum(&:quantity) }
      shortages = []
      # Bloqueo por id: dos cobros que se cruzan no se esperan en círculo.
      Product.tracked.where(id: wanted.keys).order(:id).lock.each do |product|
        quantity = wanted.fetch(product.id)
        taken = [ quantity, product.stock.to_d ].min
        shortages << { product_id: product.id, name: product.name, missing: Product.quantity(quantity - taken) } if taken < quantity
        record_taken(items.select { |item| item.product_id == product.id }, taken)
        next unless taken.positive?

        StockMovement.create!(product: product, company: @company, user: @user, work_order: @order, movement_type: :exit,
                              qty: taken, note: I18n.t("work_order.stock_note", id: @order.id))
      end
      shortages
    end

    private

    # Reparte lo descontado entre los renglones del mismo producto, en orden.
    def record_taken(items, taken)
      items.each do |item|
        part = [ item.quantity, taken ].min
        item.update_columns(stock_taken: part, updated_at: Time.current)
        taken -= part
      end
    end
  end
end
