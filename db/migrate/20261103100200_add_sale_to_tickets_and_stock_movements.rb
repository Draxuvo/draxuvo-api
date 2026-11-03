# Spec 050: el ticket gana un tercer dueño (la venta de mostrador) y el movimiento de stock apunta a la venta
# que lo originó. Una venta tiene a lo más un ticket y el ticket tiene exactamente un dueño.
class AddSaleToTicketsAndStockMovements < ActiveRecord::Migration[8.0]
  OLD_OWNER = "(work_order_id IS NULL) <> (check_id IS NULL)".freeze
  NEW_OWNER = "num_nonnulls(work_order_id, check_id, sale_id) = 1".freeze

  def up
    add_reference :tickets, :sale, foreign_key: true, index: { unique: true }
    add_reference :stock_movements, :sale, foreign_key: true
    remove_check_constraint :tickets, name: "tickets_one_owner"
    add_check_constraint :tickets, NEW_OWNER, name: "tickets_one_owner"
  end

  def down
    remove_check_constraint :tickets, name: "tickets_one_owner"
    add_check_constraint :tickets, OLD_OWNER, name: "tickets_one_owner"
    remove_reference :stock_movements, :sale, foreign_key: true
    remove_reference :tickets, :sale, foreign_key: true, index: { unique: true }
  end
end
