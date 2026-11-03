class AddAmountsToModuleChanges < ActiveRecord::Migration[8.0]
  def change
    add_column :module_changes, :amount_before_cents, :integer
    add_column :module_changes, :amount_after_cents, :integer
  end
end
