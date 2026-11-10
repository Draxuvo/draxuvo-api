# Spec 059: enlace público del menú de cada mesa (token aleatorio y regenerable). Las mesas existentes quedan sin
# token hasta que un jefe consulta sus enlaces o imprime su tarjeta.
class AddMenuTokenToDiningTables < ActiveRecord::Migration[8.0]
  def change
    add_column :dining_tables, :menu_token, :string
    add_column :dining_tables, :menu_token_generated_at, :datetime
    add_index :dining_tables, :menu_token, unique: true, where: "menu_token IS NOT NULL"
  end
end
