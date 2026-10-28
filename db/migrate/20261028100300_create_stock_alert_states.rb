# Spec 045: qué producto con stock bajo ya se detectó y avisó; se borra al reponerse (rearme).
class CreateStockAlertStates < ActiveRecord::Migration[8.0]
  def change
    create_table :stock_alert_states do |t|
      t.references :company, null: false, foreign_key: true
      t.references :product, null: false, foreign_key: { on_delete: :cascade }, index: { unique: true }
      t.datetime :detected_at, null: false
      t.datetime :notified_at
      t.timestamps
    end
  end
end
