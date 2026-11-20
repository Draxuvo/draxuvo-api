# Cuenta de un proveedor de terminal (Mercado Pago) conectada por una empresa (spec 069, data-model.md). Los tokens van
# cifrados con Active Record Encryption (`encrypts` en el modelo).
class CreateTerminalConnections < ActiveRecord::Migration[8.0]
  def change
    create_table :terminal_connections do |t|
      t.references :company, null: false, foreign_key: true, index: false
      t.string :provider, null: false
      t.string :status, null: false, default: "connected"
      t.string :account_id
      t.string :account_label
      t.text :access_token
      t.text :refresh_token
      t.datetime :token_expires_at
      t.boolean :live_mode, null: false, default: true
      t.references :connected_by, foreign_key: { to_table: :users }
      t.datetime :connected_at
      t.datetime :disconnected_at
      t.datetime :last_refreshed_at
      t.string :error_code
      t.string :error_message
      t.datetime :problem_notified_at
      t.timestamps
    end
    add_index :terminal_connections, %i[company_id provider], unique: true
    # No único: la principal y sus sucursales pueden conectar la misma cuenta (spec 069, A1).
    add_index :terminal_connections, %i[provider account_id]
  end
end
