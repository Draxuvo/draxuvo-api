# Spec 047: la conexión de WhatsApp Business de la plataforma (una sola fila). La llave va cifrada (`encrypts`).
class CreateWhatsappConnections < ActiveRecord::Migration[8.0]
  def change
    create_table :whatsapp_connections do |t|
      t.string :phone_number_id
      t.string :waba_id
      t.text :access_token
      t.string :token_hint, limit: 4
      t.string :status, null: false, default: "not_connected"
      t.string :error_code
      t.text :error_message
      t.string :verified_name
      t.string :display_phone_number
      t.datetime :last_verified_at
      t.boolean :enabled, null: false, default: false
      t.boolean :managed, null: false, default: false
      t.datetime :problem_notified_at
      t.integer :lock_version, null: false, default: 0
      t.timestamps
    end
  end
end
