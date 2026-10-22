# Spec 032: el menú del restaurante se decide por tipo de producto (`in_menu`) y las estaciones tienen un tipo
# (`kind`) para distinguir cocina y barra. La migración de datos va por regla, una sola vez.
class AddMenuAndKind < ActiveRecord::Migration[8.0]
  def up
    add_column :product_types, :in_menu, :boolean, null: false, default: true
    add_column :stations, :kind, :string, null: false, default: "kitchen"

    # Platillo y bebida quedan dentro (también los personalizados, que no se pueden clasificar); el insumo sale.
    # En modo servicio el filtro del menú no se aplica, así que sus tipos quedan como están.
    execute "UPDATE product_types SET in_menu = FALSE WHERE kind = 'supply'"
    execute "UPDATE stations SET kind = 'bar' WHERE lower(name) = 'barra'"
  end

  def down
    remove_column :stations, :kind
    remove_column :product_types, :in_menu
  end
end
