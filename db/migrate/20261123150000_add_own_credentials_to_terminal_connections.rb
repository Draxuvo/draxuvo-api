# Spec 069 (credenciales propias): el dueño o administrador conecta Mercado Pago pegando el Access Token de su propia
# aplicación, sin OAuth. `auth_method` distingue las dos formas; el aviso de una conexión con credenciales propias llega a
# una URL con `webhook_token` y se valida con su propia clave secreta (`webhook_secret`, cifrada como el token).
class AddOwnCredentialsToTerminalConnections < ActiveRecord::Migration[8.0]
  def change
    add_column :terminal_connections, :auth_method, :string, null: false, default: "oauth"
    add_column :terminal_connections, :webhook_secret, :text
    add_column :terminal_connections, :webhook_token, :string
    add_index :terminal_connections, :webhook_token, unique: true
  end
end
