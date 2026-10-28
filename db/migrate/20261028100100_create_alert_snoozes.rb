# Spec 045: alertas de tiempo pospuestas por un plazo fijo; valen para todos los jefes de la empresa.
class CreateAlertSnoozes < ActiveRecord::Migration[8.0]
  def change
    create_table :alert_snoozes do |t|
      t.references :company, null: false, foreign_key: true
      t.references :user, foreign_key: { on_delete: :nullify }
      t.string :kind, null: false
      t.string :subject_key, null: false
      t.datetime :snoozed_until, null: false
      t.timestamps
    end
    add_index :alert_snoozes, %i[company_id kind subject_key], unique: true, name: "index_alert_snoozes_on_subject"
    add_index :alert_snoozes, %i[company_id snoozed_until]
  end
end
