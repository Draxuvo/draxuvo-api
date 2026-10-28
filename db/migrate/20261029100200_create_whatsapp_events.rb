# Spec 047: historial de la configuración de WhatsApp (solo inserción; nunca guarda secretos).
class CreateWhatsappEvents < ActiveRecord::Migration[8.0]
  def change
    create_table :whatsapp_events do |t|
      t.references :user, foreign_key: { on_delete: :nullify }
      t.string :action, null: false
      t.string :target, null: false
      t.jsonb :data, null: false, default: {}
      t.string :result, null: false, default: "ok"
      t.string :meta_code
      t.datetime :created_at, null: false
    end
    add_index :whatsapp_events, :created_at, order: { created_at: :desc }
    add_index :whatsapp_events, %i[user_id action created_at], name: "index_whatsapp_events_on_user_action_and_time"
  end
end
