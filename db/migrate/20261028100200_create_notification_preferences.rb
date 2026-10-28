# Spec 045: canales por persona y empresa para los avisos de stock bajo.
class CreateNotificationPreferences < ActiveRecord::Migration[8.0]
  def change
    create_table :notification_preferences do |t|
      t.references :user, null: false, foreign_key: { on_delete: :cascade }
      t.references :company, null: false, foreign_key: true
      t.boolean :stock_email, null: false, default: true
      t.boolean :stock_whatsapp, null: false, default: false
      t.timestamps
    end
    add_index :notification_preferences, %i[user_id company_id], unique: true,
              name: "index_notification_preferences_on_user_and_company"
  end
end
