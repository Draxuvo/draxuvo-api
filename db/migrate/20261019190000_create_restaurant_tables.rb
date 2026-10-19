class CreateRestaurantTables < ActiveRecord::Migration[8.0]
  def change
    create_table :stations do |t|
      t.references :company, null: false, foreign_key: true
      t.string :name, null: false
      t.boolean :is_default, null: false, default: false
      t.boolean :active, null: false, default: true
      t.integer :position, null: false, default: 0
      t.timestamps
    end
    add_index :stations, %i[company_id name], unique: true

    create_table :dining_tables do |t|
      t.references :company, null: false, foreign_key: true
      t.string :name, null: false
      t.boolean :active, null: false, default: true
      t.integer :position, null: false, default: 0
      t.timestamps
    end
    add_index :dining_tables, %i[company_id name], unique: true

    create_table :checks do |t|
      t.references :company, null: false, foreign_key: true
      t.references :dining_table, foreign_key: true
      t.string :takeout_name
      t.references :opened_by, null: false, foreign_key: { to_table: :users }
      t.references :waiter, null: false, foreign_key: { to_table: :users }
      t.integer :status, null: false, default: 0
      t.decimal :total, precision: 10, scale: 2, null: false, default: 0
      t.datetime :opened_at, null: false
      t.datetime :closed_at
      t.text :cancel_reason
      t.timestamps
    end
    add_index :checks, :dining_table_id, unique: true, where: "status = 0", name: "index_checks_on_open_dining_table"
    add_index :checks, %i[company_id status]

    create_table :kitchen_orders do |t|
      t.references :company, null: false, foreign_key: true
      t.references :check, null: false, foreign_key: true
      t.references :sent_by, null: false, foreign_key: { to_table: :users }
      t.datetime :sent_at, null: false
      t.integer :number, null: false
      t.timestamps
    end
    add_index :kitchen_orders, %i[check_id number], unique: true

    create_table :check_items do |t|
      t.references :company, null: false, foreign_key: true
      t.references :check, null: false, foreign_key: true
      t.references :kitchen_order, foreign_key: true
      t.references :product, foreign_key: true
      t.string :name, null: false
      t.decimal :unit_price, precision: 10, scale: 2, null: false, default: 0
      t.integer :quantity, null: false, default: 1
      t.text :note
      t.references :station, foreign_key: true
      t.integer :status, null: false, default: 0
      t.datetime :preparing_at
      t.datetime :ready_at
      t.datetime :delivered_at
      t.datetime :cancelled_at
      t.text :cancel_reason
      t.references :cancelled_by, foreign_key: { to_table: :users }
      t.timestamps
    end
    add_index :check_items, %i[station_id status]

    create_table :check_payments do |t|
      t.references :company, null: false, foreign_key: true
      t.references :check, null: false, foreign_key: true
      t.integer :payment_method, null: false
      t.decimal :amount, precision: 10, scale: 2, null: false
      t.string :reference
      t.decimal :amount_received, precision: 10, scale: 2
      t.decimal :change_given, precision: 10, scale: 2
      t.references :created_by, null: false, foreign_key: { to_table: :users }
      t.timestamps
    end
  end
end
