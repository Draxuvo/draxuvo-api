# Spec 054 (H-49): al cobrar una orden de trabajo se descuenta del inventario lo vendido. Cada renglón guarda lo que de
# verdad salió (puede ser menos de lo pedido si la existencia no alcanzó) para devolver exactamente eso al anular el cobro.
# Las órdenes cobradas antes de esta spec quedan en 0: no regresan existencias que nunca salieron.
class AddStockTakenToWorkOrderItems < ActiveRecord::Migration[8.0]
  def change
    add_column :work_order_items, :stock_taken, :decimal, precision: 12, scale: 3, null: false, default: 0
  end
end
