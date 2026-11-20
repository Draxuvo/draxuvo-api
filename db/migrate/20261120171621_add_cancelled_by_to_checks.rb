# Spec 070: quién liberó la mesa (canceló la cuenta). Las cuentas canceladas antes quedan sin el dato.
class AddCancelledByToChecks < ActiveRecord::Migration[8.0]
  def change
    add_reference :checks, :cancelled_by, foreign_key: { to_table: :users, on_delete: :nullify }, index: true, null: true
  end
end
