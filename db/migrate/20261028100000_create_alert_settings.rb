# Spec 045: tiempos límite, hora del resumen y zona horaria de las alertas de cada empresa.
class CreateAlertSettings < ActiveRecord::Migration[8.0]
  def change
    create_table :alert_settings do |t|
      t.references :company, null: false, foreign_key: true, index: { unique: true }
      t.jsonb :thresholds, null: false, default: {}
      t.integer :summary_hour, null: false, default: 8, limit: 2
      t.string :time_zone, null: false, default: "America/Mexico_City"
      t.timestamps
    end
  end
end
