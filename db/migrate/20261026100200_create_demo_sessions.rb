# Spec 039: cada apertura de una demo. Sobrevive a la purga de la empresa para el seguimiento comercial,
# por eso company_id y user_id se anulan (on_delete: :nullify). No guarda IP ni agente de navegador.
class CreateDemoSessions < ActiveRecord::Migration[8.0]
  def change
    create_table :demo_sessions do |t|
      t.references :company, foreign_key: { on_delete: :nullify }
      t.references :user, foreign_key: { on_delete: :nullify }
      t.references :demo_invite, foreign_key: true
      t.string :plan, null: false
      t.string :scenario, null: false
      t.string :locale, null: false
      t.string :contact_name
      t.string :contact_email
      t.string :contact_phone
      t.datetime :expires_at, null: false
      t.datetime :ended_at
      t.string :ended_reason
      t.datetime :purged_at
      t.timestamps
    end
    add_index :demo_sessions, :created_at
    add_index :demo_sessions, %i[purged_at expires_at]
  end
end
