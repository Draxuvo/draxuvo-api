# Terminales de cobro del negocio (spec 015, FR-018). El proveedor es texto validado en el modelo.
class CreatePaymentTerminals < ActiveRecord::Migration[8.0]
  def change
    create_table :payment_terminals do |t|
      t.references :company, null: false, foreign_key: true
      t.string :name, null: false
      t.string :provider, null: false
      t.boolean :active, null: false, default: true
      t.timestamps
    end
    add_index :payment_terminals, "company_id, lower(name)", unique: true, name: "index_payment_terminals_on_company_and_lower_name"
  end
end
