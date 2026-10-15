# El concepto ya no es un paso: sin estado ni fecha de hecho (spec 007, R3).
class RemoveStepColumnsFromWorkOrderItems < ActiveRecord::Migration[8.0]
  def change
    remove_column :work_order_items, :status, :integer
    remove_column :work_order_items, :completed_at, :datetime
  end
end
