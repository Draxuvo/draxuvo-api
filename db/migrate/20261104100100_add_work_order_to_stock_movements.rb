# Spec 054 (H-49): el movimiento de existencias apunta a la orden de trabajo que lo originó, igual que `sale_id` apunta a
# la venta. Una entrada con `work_order_id` es la devolución de un cobro anulado, no una compra (no cuenta en Gastos).
class AddWorkOrderToStockMovements < ActiveRecord::Migration[8.0]
  def change
    add_reference :stock_movements, :work_order, foreign_key: true
  end
end
