# Spec 057 (FR-012): qué alertas operativas ya se avisaron por push. Las alertas no se guardan (spec 045); esta fila
# evita repetir el aviso y `rearm` permite avisar una vez más al terminar una posposición.
class CreatePushAlertNotices < ActiveRecord::Migration[8.0]
  def change
    create_table :push_alert_notices do |t|
      t.references :company, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.string :kind, null: false
      t.string :subject_key, null: false
      t.datetime :notified_at, null: false
      t.boolean :rearm, null: false, default: false
      t.timestamps
    end
    add_index :push_alert_notices, %i[company_id kind subject_key], unique: true, name: "index_push_alert_notices_unique"
  end
end
