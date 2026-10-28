# Spec 044: las unidades son datos de referencia y producción las perdió al vaciarse. Se reponen al migrar
# (idempotente: no toca las que ya existen).
class SeedUnits < ActiveRecord::Migration[8.0]
  def up
    Unit.reset_column_information
    Unit.ensure_catalog!
  end

  def down; end
end
