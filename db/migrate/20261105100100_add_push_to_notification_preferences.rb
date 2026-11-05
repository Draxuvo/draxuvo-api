# Spec 057: un interruptor por tipo de aviso push, por persona y empresa. Todos encendidos por omisión.
class AddPushToNotificationPreferences < ActiveRecord::Migration[8.0]
  def change
    change_table :notification_preferences, bulk: true do |t|
      t.boolean :push_check_ready, null: false, default: true
      t.boolean :push_work_order_assigned, null: false, default: true
      t.boolean :push_operational_alerts, null: false, default: true
      t.boolean :push_low_stock, null: false, default: true
    end
  end
end
