# Estados nuevos de la orden (spec 007). Los enteros se conservan: pending→open (0), in_progress (1),
# in_review→done (2), completed→paid (3), cancelled (4). Solo cambia el significado de 3 cuando
# no hay cobro: esas órdenes bajan a done (2).
class RemapWorkOrderStatuses < ActiveRecord::Migration[8.0]
  def up
    execute "UPDATE work_orders SET status = 0 WHERE status IS NULL"
    execute <<~SQL
      UPDATE work_orders SET status = 2
      WHERE status = 3
        AND NOT EXISTS (
          SELECT 1 FROM tickets WHERE tickets.work_order_id = work_orders.id AND tickets.status = 1
        )
    SQL
    change_column_default :work_orders, :status, from: nil, to: 0
    change_column_null :work_orders, :status, false
    add_column :work_orders, :customer_name, :string
    add_column :work_orders, :customer_phone, :string
    add_column :work_orders, :customer_address, :text
    add_column :work_orders, :started_at, :datetime
    add_column :work_orders, :cancel_reason, :text
  end

  def down
    remove_column :work_orders, :cancel_reason
    remove_column :work_orders, :started_at
    remove_column :work_orders, :customer_address
    remove_column :work_orders, :customer_phone
    remove_column :work_orders, :customer_name
    change_column_null :work_orders, :status, true
    change_column_default :work_orders, :status, from: 0, to: nil
  end
end
