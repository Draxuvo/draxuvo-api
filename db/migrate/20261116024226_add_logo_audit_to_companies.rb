# Spec 063: quién y cuándo cambió el logo de la empresa por última vez (FR-013). El logo es un adjunto de Active Storage.
class AddLogoAuditToCompanies < ActiveRecord::Migration[8.0]
  def change
    add_reference :companies, :logo_updated_by, foreign_key: { to_table: :users, on_delete: :nullify }, null: true
    add_column :companies, :logo_updated_at, :datetime
  end
end
