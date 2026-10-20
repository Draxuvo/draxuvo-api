# Tipos iniciales por giro, unidades nuevas y clasificación de los productos existentes (spec 016, research R6).
# Usa SQL y no los modelos de la app, para que la migración no dependa de cómo cambien después.
class ClassifyProductsByType < ActiveRecord::Migration[8.0]
  DEFAULTS = {
    1 => [ [ "Platillo", "sold", true, false, false, "pza" ], [ "Bebida", "counted_sold", true, true, false, "pza" ],
           [ "Insumo", "supply", false, true, true, "kg" ] ],
    0 => [ [ "Servicio", "sold", true, false, false, "serv" ], [ "Refacción", "counted_sold", true, true, false, "pza" ],
           [ "Material", "supply", false, true, true, "pza" ] ]
  }.freeze
  UNITS = [ [ "g", "Gramo", "peso", 7 ], [ "ml", "Mililitro", "volumen", 8 ], [ "paq", "Paquete", "cantidad", 9 ] ].freeze

  def up
    UNITS.each do |key, name, group, position|
      execute <<~SQL
        INSERT INTO units (key, name, "group", position, created_at, updated_at)
        VALUES (#{quote(key)}, #{quote(name)}, #{quote(group)}, #{position}, NOW(), NOW())
        ON CONFLICT (key) DO NOTHING
      SQL
    end

    select_rows("SELECT id, order_mode FROM companies").each do |company_id, order_mode|
      DEFAULTS.fetch(order_mode.to_i, DEFAULTS[0]).each_with_index do |(name, kind, sellable, counted, fractional, unit), index|
        execute <<~SQL
          INSERT INTO product_types (company_id, name, kind, sellable, counted, fractional, default_unit_key, active, position, created_at, updated_at)
          SELECT #{company_id}, #{quote(name)}, #{quote(kind)}, #{sellable}, #{counted}, #{fractional}, #{quote(unit)}, TRUE, #{index + 1}, NOW(), NOW()
          WHERE NOT EXISTS (SELECT 1 FROM product_types WHERE company_id = #{company_id} AND kind = #{quote(kind)})
        SQL
      end
    end

    # Restaurante (modo pedido): "controla inventario" decide. Servicio: el inventario siempre contó existencias,
    # así que lo que tiene existencia o mínimo es refacción.
    execute <<~SQL
      UPDATE products p SET product_type_id = t.id
      FROM product_types t, companies c
      WHERE t.company_id = p.company_id AND c.id = p.company_id AND p.product_type_id IS NULL AND t.kind = CASE
        WHEN NOT p.available THEN 'supply'
        WHEN p.tracks_stock THEN 'counted_sold'
        WHEN c.order_mode = 0 AND (COALESCE(p.stock, 0) > 0 OR COALESCE(p.min_stock, 0) > 0) THEN 'counted_sold'
        ELSE 'sold' END
    SQL
    execute <<~SQL
      UPDATE products p SET available = TRUE
      FROM product_types t WHERE t.id = p.product_type_id AND t.kind = 'supply' AND NOT p.available
    SQL
    execute <<~SQL
      UPDATE products p SET tracks_stock = t.counted FROM product_types t WHERE t.id = p.product_type_id
    SQL
    change_column_null :products, :product_type_id, false
  end

  def down
    change_column_null :products, :product_type_id, true
    execute "UPDATE products SET product_type_id = NULL"
    execute "DELETE FROM product_types"
    execute "DELETE FROM units WHERE key IN ('g', 'ml', 'paq')"
  end

  private

  def quote(value) = connection.quote(value)
end
