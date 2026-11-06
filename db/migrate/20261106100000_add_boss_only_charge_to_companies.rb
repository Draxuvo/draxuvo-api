# Spec 058: «Cobro solo por jefes». Apagada por omisión: las empresas actuales siguen cobrando igual.
class AddBossOnlyChargeToCompanies < ActiveRecord::Migration[8.0]
  def change
    add_column :companies, :boss_only_charge, :boolean, null: false, default: false
  end
end
