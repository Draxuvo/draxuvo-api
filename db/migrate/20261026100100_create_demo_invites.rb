# Spec 039: accesos a la demo que genera el equipo comercial. El token solo se guarda como huella SHA-256.
class CreateDemoInvites < ActiveRecord::Migration[8.0]
  def change
    create_table :demo_invites do |t|
      t.string :plan, null: false
      t.string :scenario, null: false
      t.string :label, null: false
      t.string :token_digest, null: false
      t.references :created_by, foreign_key: { to_table: :users }
      t.datetime :expires_at, null: false
      t.datetime :revoked_at
      t.timestamps
    end
    add_index :demo_invites, :token_digest, unique: true
  end
end
