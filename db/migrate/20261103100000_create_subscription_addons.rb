# Spec 050: módulos extra contratados sobre el plan (por ahora, el punto de venta). Cada fila es un extra de una
# suscripción; `ends_at` marca el fin del acceso tras una baja (el módulo sigue activo hasta esa fecha).
class CreateSubscriptionAddons < ActiveRecord::Migration[8.0]
  def change
    create_table :subscription_addons do |t|
      t.references :subscription, null: false, foreign_key: true
      t.references :company, null: false, foreign_key: true
      t.string :module, null: false
      t.string :stripe_item_id
      t.integer :amount_cents, null: false, default: 0
      t.datetime :started_at, null: false
      t.datetime :ends_at
      t.timestamps
    end
    add_index :subscription_addons, %i[subscription_id module], unique: true
  end
end
