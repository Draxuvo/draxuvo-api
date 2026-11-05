# Spec 057 (FR-023): bitácora de avisos push, una fila por persona y aviso. Guarda los tickets de Expo con el id del
# dispositivo, nunca el token.
class CreatePushDeliveries < ActiveRecord::Migration[8.0]
  def change
    create_table :push_deliveries do |t|
      t.references :company, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.references :user, foreign_key: { on_delete: :nullify }
      t.string :kind, null: false
      t.string :subject_key, null: false, limit: 200
      t.string :status, null: false
      t.integer :devices_count, null: false, default: 0
      t.jsonb :tickets, null: false, default: []
      t.string :error, limit: 200
      t.integer :attempts, null: false, default: 0
      t.datetime :receipts_checked_at
      t.timestamps
    end
    add_index :push_deliveries, %i[company_id kind subject_key created_at], name: "index_push_deliveries_on_subject"
    add_index :push_deliveries, :created_at
  end
end
