class RemovePlanFromCompanies < ActiveRecord::Migration[8.0]
  def change
    remove_column :companies, :plan, :integer
  end
end
