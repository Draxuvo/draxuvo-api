class AddInitialToStockMovements < ActiveRecord::Migration[8.0]
  def change
    add_column :stock_movements, :initial, :boolean, null: false, default: false
  end
end
