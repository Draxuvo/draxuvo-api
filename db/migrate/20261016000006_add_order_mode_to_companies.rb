# Modo de órdenes por empresa (spec 007, R8): 0 service, 1 order.
class AddOrderModeToCompanies < ActiveRecord::Migration[8.0]
  def change
    add_column :companies, :order_mode, :integer, null: false, default: 0
  end
end
