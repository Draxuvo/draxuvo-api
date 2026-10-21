# Icono opcional del producto y icono sugerido del tipo (spec 026): clave del catálogo ProductIcons.
class AddIconToProductsAndProductTypes < ActiveRecord::Migration[8.0]
  def change
    add_column :products, :icon, :string
    add_column :product_types, :icon, :string
  end
end
