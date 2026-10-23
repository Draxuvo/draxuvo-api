# Spec 034: códigos de barras por producto, importaciones en segundo plano, conteos físicos en borrador y
# quién hizo cada movimiento de stock.
class AddBarcodesImportsAndCounts < ActiveRecord::Migration[8.0]
  def change
    create_table :product_barcodes do |t|
      t.references :company, null: false, foreign_key: true
      t.references :product, null: false, foreign_key: true
      t.string :code, null: false, limit: 64
      t.timestamps
    end
    add_index :product_barcodes, %i[company_id code], unique: true

    create_table :product_imports do |t|
      t.references :company, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.integer :status, null: false, default: 0
      t.string :filename
      t.boolean :allow_icon, null: false, default: false
      t.integer :total_rows, null: false, default: 0
      t.integer :processed_rows, null: false, default: 0
      t.integer :created_count, null: false, default: 0
      t.integer :updated_count, null: false, default: 0
      t.integer :unchanged_count, null: false, default: 0
      t.jsonb :errors_list, null: false, default: []
      t.integer :errors_total, null: false, default: 0
      t.binary :file_data
      t.datetime :started_at
      t.datetime :finished_at
      t.timestamps
    end
    add_index :product_imports, %i[company_id created_at]

    create_table :stock_counts do |t|
      t.references :company, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.integer :status, null: false, default: 0
      t.string :name
      t.datetime :confirmed_at
      t.references :confirmed_by, foreign_key: { to_table: :users }
      t.jsonb :result, null: false, default: {}
      t.timestamps
    end

    create_table :stock_count_items do |t|
      t.references :stock_count, null: false, foreign_key: true
      t.references :product, null: false, foreign_key: true
      t.decimal :counted_qty, precision: 12, scale: 3, null: false, default: 0
      t.decimal :baseline_stock, precision: 12, scale: 3, null: false, default: 0
      t.timestamps
    end
    add_index :stock_count_items, %i[stock_count_id product_id], unique: true

    add_reference :stock_movements, :user, foreign_key: true
  end
end
