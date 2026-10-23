# Spec 035: formatos de etiqueta propios de cada empresa y la secuencia de códigos de barras propios
# (solo avanza: un código generado nunca se reasigna).
class AddLabelFormatsAndBarcodeSequence < ActiveRecord::Migration[8.0]
  def change
    add_column :companies, :barcode_sequence, :bigint, null: false, default: 0

    create_table :label_formats do |t|
      t.references :company, null: false, foreign_key: true
      t.string :name, null: false, limit: 60
      t.string :kind, null: false, default: "sheet"
      t.decimal :page_width_mm, precision: 6, scale: 2, null: false
      t.decimal :page_height_mm, precision: 6, scale: 2, null: false
      t.integer :columns, null: false, default: 1
      t.integer :rows, null: false, default: 1
      t.decimal :label_width_mm, precision: 6, scale: 2, null: false
      t.decimal :label_height_mm, precision: 6, scale: 2, null: false
      t.decimal :margin_top_mm, precision: 6, scale: 2, null: false, default: 0
      t.decimal :margin_left_mm, precision: 6, scale: 2, null: false, default: 0
      t.decimal :gap_x_mm, precision: 6, scale: 2, null: false, default: 0
      t.decimal :gap_y_mm, precision: 6, scale: 2, null: false, default: 0
      t.timestamps
    end
    add_index :label_formats, "company_id, lower(name)", unique: true, name: "index_label_formats_on_company_and_lower_name"
  end
end
