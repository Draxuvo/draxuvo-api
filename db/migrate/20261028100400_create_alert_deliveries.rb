# Spec 045: registro de los avisos de stock bajo enviados (solo inserción); evita repetir el resumen del día.
class CreateAlertDeliveries < ActiveRecord::Migration[8.0]
  def change
    create_table :alert_deliveries do |t|
      t.references :company, null: false, foreign_key: true
      t.references :user, foreign_key: { on_delete: :nullify }
      t.string :channel, null: false
      t.string :kind, null: false
      t.bigint :product_ids, array: true, null: false, default: []
      t.string :status, null: false
      t.text :error
      t.date :sent_on, null: false
      t.timestamps
    end
    add_index :alert_deliveries, %i[user_id company_id channel sent_on], unique: true, where: "kind = 'daily'",
              name: "index_alert_deliveries_one_daily_per_day"
  end
end
