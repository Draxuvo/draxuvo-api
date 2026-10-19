class RestaurantTicketsProducts < ActiveRecord::Migration[8.0]
  def change
    add_reference :tickets, :check, foreign_key: true, index: { unique: true }
    change_column_null :tickets, :work_order_id, true
    add_check_constraint :tickets, "(work_order_id IS NULL) <> (check_id IS NULL)", name: "tickets_one_owner"

    add_column :products, :tracks_stock, :boolean, null: false, default: false
    add_reference :products, :station, foreign_key: true
  end
end
