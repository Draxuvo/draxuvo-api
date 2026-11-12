# Spec 062: una purga de demo que falla se marca y pasa al final del lote, y borrar un usuario se lleva sus llaves de
# idempotencia (antes las llaves impedían borrar al dueño de una demo y atoraban toda la limpieza).
class AddPurgeFailedAtToDemoSessions < ActiveRecord::Migration[8.0]
  def change
    add_column :demo_sessions, :purge_failed_at, :datetime

    remove_foreign_key :idempotency_keys, :users
    add_foreign_key :idempotency_keys, :users, on_delete: :cascade
  end
end
