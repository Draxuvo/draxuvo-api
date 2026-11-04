# Regresa al inventario lo que se descontó al cobrar una orden de trabajo cuando se anula el cobro (spec 054, H-49).
# Devuelve exactamente `stock_taken` (que puede ser menos de lo vendido) y lo deja en 0, así que repetirlo no devuelve
# nada otra vez. Productos borrados o que ya no se cuentan no se tocan. Las órdenes cobradas antes de la spec tienen
# `stock_taken` en 0 y no regresan existencias que nunca salieron.
module WorkOrders
  class RestoreStock
    def self.call(order, user) = new(order, user).call

    def initialize(order, user)
      @order = order
      @user = user
      @company = order.company
    end

    def call
      items = @order.work_order_items.where.not(product_id: nil).where("stock_taken > 0").to_a
      back = items.group_by(&:product_id).transform_values { |rows| rows.sum(&:stock_taken) }
      Product.tracked.where(id: back.keys).order(:id).lock.each do |product|
        StockMovement.create!(product: product, company: @company, user: @user, work_order: @order, movement_type: :entry,
                              qty: back.fetch(product.id), note: I18n.t("work_order.stock_cancel_note", id: @order.id))
      end
      @order.work_order_items.where("stock_taken > 0").update_all(stock_taken: 0, updated_at: Time.current)
    end
  end
end
