# Sucursales del plan Empresa (spec 004, R17): un solo nivel. Sin llave foránea a propósito:
# si la principal se borra, sus sucursales se bloquean pero no se borran (FR-029).
class AddParentCompanyToCompanies < ActiveRecord::Migration[8.0]
  def change
    add_column :companies, :parent_company_id, :bigint
    add_index :companies, :parent_company_id
  end
end
