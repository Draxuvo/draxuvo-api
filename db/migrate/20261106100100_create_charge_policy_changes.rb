# Spec 058: bitácora de los cambios de «Cobro solo por jefes» hechos por el super admin. Solo se inserta.
class CreateChargePolicyChanges < ActiveRecord::Migration[8.0]
  def change
    create_table :charge_policy_changes do |t|
      t.references :company, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.references :actor, null: false, foreign_key: { to_table: :users }
      t.boolean :enabled, null: false
      t.datetime :created_at, null: false
    end
    add_index :charge_policy_changes, [ :company_id, :created_at ]
  end
end
