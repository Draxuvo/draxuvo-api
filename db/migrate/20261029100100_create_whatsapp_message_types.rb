# Spec 047: un tipo de mensaje de WhatsApp (código de verificación, stock bajo, tickets) con su interruptor y su plantilla.
class CreateWhatsappMessageTypes < ActiveRecord::Migration[8.0]
  def change
    create_table :whatsapp_message_types do |t|
      t.string :kind, null: false
      t.boolean :enabled, null: false, default: false
      t.string :template_name
      t.string :template_language, null: false, default: "es_MX"
      t.string :template_status, null: false, default: "unknown"
      t.text :template_detail
      t.datetime :template_checked_at
      t.datetime :problem_notified_at
      t.integer :lock_version, null: false, default: 0
      t.timestamps
    end
    add_index :whatsapp_message_types, :kind, unique: true
  end
end
