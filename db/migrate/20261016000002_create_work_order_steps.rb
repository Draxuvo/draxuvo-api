class CreateWorkOrderSteps < ActiveRecord::Migration[8.0]
  def change
    create_table :work_order_steps do |t|
      t.references :work_order, null: false, foreign_key: true
      t.string :description, null: false
      t.integer :position, null: false, default: 0
      t.datetime :done_at
      t.references :done_by, polymorphic: true
      t.timestamps
    end
  end
end
