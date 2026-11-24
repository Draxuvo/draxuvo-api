# Spec 073: bitácora de inicios de sesión. Un renglón por intento en POST /auth/login, de solo inserción y con 90 días de
# vida (LoginAttempts::PurgeJob). Nunca guarda la contraseña ni el token. Si se borra la persona, el intento conserva el
# correo escrito y pierde el enlace (on_delete: :nullify).
class CreateLoginAttempts < ActiveRecord::Migration[8.0]
  def change
    create_table :login_attempts do |t|
      t.string :result, null: false
      t.string :email, null: false, limit: 254
      t.references :user, null: true, foreign_key: { on_delete: :nullify }, index: false
      t.inet :ip
      t.string :user_agent, limit: 500
      t.string :channel, null: false
      t.string :client_version, limit: 50
      t.boolean :demo, null: false, default: false
      t.datetime :created_at, null: false
    end

    add_index :login_attempts, :created_at
    add_index :login_attempts, %i[email created_at]
    add_index :login_attempts, %i[ip created_at]
    add_index :login_attempts, %i[user_id created_at]
    add_index :login_attempts, %i[result created_at]
  end
end
