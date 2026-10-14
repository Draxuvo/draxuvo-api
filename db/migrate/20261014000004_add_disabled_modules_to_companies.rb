class AddDisabledModulesToCompanies < ActiveRecord::Migration[8.0]
  def change
    add_column :companies, :disabled_modules, :string, array: true, default: [], null: false
  end
end
