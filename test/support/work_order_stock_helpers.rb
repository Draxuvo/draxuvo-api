# Ayudantes para probar el descuento de existencias en órdenes de trabajo (spec 054).
module WorkOrderStockHelpers
  # Orden terminada de pos_co con renglones de catálogo `[producto, cantidad]` y un concepto libre opcional.
  def done_order(*lines, free: nil, company: companies(:pos_co))
    order = WorkOrder.create!(company: company, title: "Orden #{SecureRandom.hex(3)}", created_by: users(:pos_admin),
                              status: :done, completed_at: Time.current)
    lines.each_with_index do |(product, quantity), index|
      order.work_order_items.create!(product: product, description: product.name, quantity: quantity,
                                     unit_price: product.price, position: index)
    end
    order.work_order_items.create!(description: "Mano de obra", quantity: 1, unit_price: free, position: lines.size) if free
    order.recalculate_total!
    order.reload
  end

  def stock_context(user = users(:pos_admin), role: "admin")
    WorkOrders::Transition::Context.new(user: user, role: role, employee: nil)
  end

  # Cobra en efectivo por el total y devuelve la transición (para leer `shortages`).
  def charge_order(order, user = users(:pos_admin))
    transition = WorkOrders::Transition.new(order, :charge, stock_context(user), payments: [ { method: "cash", amount_received: order.reload.total.to_s } ])
    transition.call
    transition
  end

  def void_order(order, user = users(:pos_admin), reason: "Error de captura")
    WorkOrders::Transition.call(order, :void_charge, stock_context(user), reason: reason)
  end
end

ActiveSupport::TestCase.include WorkOrderStockHelpers
