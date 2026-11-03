# Spec 050: venta de mostrador. Una venta abierta es un borrador de quien la abrió; al cobrarla genera un ticket.
# Los renglones guardan el nombre, la clave y el precio del momento, y cuánto stock se descontó de verdad.
class CreateSalesAndSaleItems < ActiveRecord::Migration[8.0]
  def change
    create_table :sales do |t|
      t.references :company, null: false, foreign_key: true
      t.integer :status, null: false, default: 0
      t.decimal :total, precision: 10, scale: 2, null: false, default: 0
      t.references :opened_by, null: false, foreign_key: { to_table: :users }
      t.references :charged_by, foreign_key: { to_table: :users }
      t.datetime :paid_at
      t.datetime :cancelled_at
      t.references :cancelled_by, foreign_key: { to_table: :users }
      t.text :cancel_reason
      t.integer :lock_version, null: false, default: 0
      t.timestamps
    end
    add_index :sales, %i[company_id status created_at]
    add_index :sales, %i[company_id opened_by_id status]

    create_table :sale_items do |t|
      t.references :sale, null: false, foreign_key: true
      t.references :company, null: false, foreign_key: true
      t.references :product, foreign_key: true
      t.string :name, null: false
      t.string :sku
      t.decimal :unit_price, precision: 10, scale: 2, null: false
      t.decimal :quantity, precision: 10, scale: 3, null: false
      t.decimal :subtotal, precision: 10, scale: 2, null: false
      t.decimal :stock_taken, precision: 10, scale: 3
      t.timestamps
    end
    add_index :sale_items, %i[sale_id product_id], unique: true, where: "product_id IS NOT NULL",
                                                   name: "index_sale_items_on_sale_and_product"
  end
end
