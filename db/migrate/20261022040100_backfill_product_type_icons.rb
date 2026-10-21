# Icono sugerido de los tipos iniciales que ya existen (spec 026); los personalizados quedan sin icono.
class BackfillProductTypeIcons < ActiveRecord::Migration[8.0]
  def up
    execute <<~SQL
      UPDATE product_types SET icon = CASE
        WHEN companies.order_mode = 1 AND product_types.kind = 'sold' THEN 'utensils'
        WHEN companies.order_mode = 1 AND product_types.kind = 'counted_sold' THEN 'cup'
        WHEN product_types.kind = 'supply' THEN 'box'
        WHEN companies.order_mode = 0 AND product_types.kind = 'sold' THEN 'wrench'
        WHEN companies.order_mode = 0 AND product_types.kind = 'counted_sold' THEN 'gear'
      END
      FROM companies
      WHERE companies.id = product_types.company_id AND product_types.kind IS NOT NULL AND product_types.icon IS NULL
    SQL
  end

  def down
    execute "UPDATE product_types SET icon = NULL WHERE kind IS NOT NULL"
  end
end
