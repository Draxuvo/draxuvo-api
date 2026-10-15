class CreateWorkOrderEvents < ActiveRecord::Migration[8.0]
  def change
    create_table :work_order_events do |t|
      t.references :work_order, null: false, foreign_key: true, index: false
      t.integer :kind, null: false
      t.references :actor, polymorphic: true, null: false
      t.jsonb :data, null: false, default: {}
      t.datetime :created_at, null: false
    end
    add_index :work_order_events, %i[work_order_id created_at]
  end
end
