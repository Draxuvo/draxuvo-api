# Spec 039: marca las empresas de demostración (una por visita). Decide el bloqueo de efectos externos y qué borra la purga.
class AddDemoToCompanies < ActiveRecord::Migration[8.0]
  def change
    add_column :companies, :demo, :boolean, null: false, default: false
    add_index :companies, :demo, where: "demo", name: "index_companies_on_demo_true"
  end
end
