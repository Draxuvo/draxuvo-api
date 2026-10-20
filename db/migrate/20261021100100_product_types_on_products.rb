# Tipo y unidad en cada producto, y existencias con decimales para los tipos que los admiten (spec 016).
class ProductTypesOnProducts < ActiveRecord::Migration[8.0]
  def up
    add_reference :products, :product_type, foreign_key: true
    add_column :products, :unit_key, :string
    change_column :products, :stock, :decimal, precision: 12, scale: 3, default: 0
    change_column :products, :min_stock, :decimal, precision: 12, scale: 3
    change_column :stock_movements, :qty, :decimal, precision: 12, scale: 3
  end

  def down
    change_column :stock_movements, :qty, :integer, using: "ROUND(qty)::integer"
    change_column :products, :min_stock, :integer, using: "ROUND(min_stock)::integer"
    change_column :products, :stock, :integer, default: nil, using: "ROUND(stock)::integer"
    remove_column :products, :unit_key
    remove_reference :products, :product_type, foreign_key: true
  end
end
