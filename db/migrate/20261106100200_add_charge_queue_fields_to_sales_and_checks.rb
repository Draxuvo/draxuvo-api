# Spec 058: «Pasar a cobro» en la venta de mostrador y «Pedir cobro» en la cuenta de mesa.
class AddChargeQueueFieldsToSalesAndChecks < ActiveRecord::Migration[8.0]
  def change
    add_column :sales, :submitted_at, :datetime
    add_column :sales, :returned_at, :datetime
    add_reference :sales, :returned_by, foreign_key: { to_table: :users }
    add_index :sales, [ :company_id, :submitted_at ], where: "status = 0 AND submitted_at IS NOT NULL",
                                                      name: "index_sales_on_company_queued"

    add_column :checks, :charge_requested_at, :datetime
    add_reference :checks, :charge_requested_by, foreign_key: { to_table: :users }
    add_index :checks, :company_id, where: "status = 0 AND charge_requested_at IS NOT NULL",
                                    name: "index_checks_on_company_charge_requested"
  end
end
