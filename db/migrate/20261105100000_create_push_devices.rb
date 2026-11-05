# Spec 057: teléfonos donde una persona tiene sesión y aceptó avisos push. El dispositivo es de la persona (no de una
# empresa); el token de Expo es único y pasa a quien inicie sesión en ese teléfono.
class CreatePushDevices < ActiveRecord::Migration[8.0]
  def change
    create_table :push_devices do |t|
      t.references :user, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.string :token, null: false, limit: 255
      t.string :platform, null: false
      t.string :locale, null: false, default: "es"
      t.string :app_version, limit: 32
      t.datetime :last_seen_at, null: false
      t.datetime :disabled_at
      t.string :disabled_reason
      t.timestamps
    end
    add_index :push_devices, :token, unique: true
    add_index :push_devices, :user_id, where: "disabled_at IS NULL", name: "index_push_devices_active_by_user"
  end
end
