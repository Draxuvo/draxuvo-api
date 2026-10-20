# Tipos de producto por empresa (spec 016): deciden si un producto se vende, se cuenta y admite decimales.
class CreateProductTypes < ActiveRecord::Migration[8.0]
  def change
    create_table :product_types do |t|
      t.references :company, null: false, foreign_key: true
      t.string :name, null: false
      t.string :kind
      t.boolean :sellable, null: false, default: true
      t.boolean :counted, null: false, default: false
      t.boolean :fractional, null: false, default: false
      t.string :default_unit_key, null: false, default: "pza"
      t.boolean :active, null: false, default: true
      t.integer :position, null: false, default: 0
      t.timestamps
    end
    add_index :product_types, "company_id, lower(name)", unique: true, name: "index_product_types_on_company_and_lower_name"
  end
end
