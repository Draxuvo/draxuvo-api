# Spec 058: aviso push «Por cobrar» para dueño y administrador, encendido por omisión.
class AddPushChargePendingToNotificationPreferences < ActiveRecord::Migration[8.0]
  def change
    add_column :notification_preferences, :push_charge_pending, :boolean, null: false, default: true
  end
end
