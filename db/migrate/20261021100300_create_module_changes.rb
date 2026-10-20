# Registro de cada cambio de módulo de una empresa hecho por el super admin (spec 017, FR-009). Solo se inserta.
class CreateModuleChanges < ActiveRecord::Migration[8.0]
  def change
    create_table :module_changes do |t|
      t.references :company, null: false, foreign_key: true
      t.references :actor, null: false, foreign_key: { to_table: :users }
      t.string :module, null: false
      t.boolean :enabled, null: false
      t.datetime :created_at, null: false
    end
    add_index :module_changes, [ :company_id, :created_at ]
  end
end
