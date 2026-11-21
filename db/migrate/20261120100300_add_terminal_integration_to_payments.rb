# Terminales ligadas a una conexión y pagos confirmados por el proveedor (spec 069, data-model.md).
class AddTerminalIntegrationToPayments < ActiveRecord::Migration[8.0]
  def change
    add_reference :payment_terminals, :terminal_connection, foreign_key: true
    add_column :payment_terminals, :device_id, :string
    add_column :payment_terminals, :device_mode, :string
    # Un dispositivo, una terminal de Draxuvo en toda la plataforma (FR-009).
    add_index :payment_terminals, %i[provider device_id], unique: true, where: "device_id IS NOT NULL",
                                                          name: "index_payment_terminals_on_provider_device"

    add_reference :ticket_payments, :terminal_charge, foreign_key: true, index: { unique: true }
    add_reference :check_payments, :terminal_charge, foreign_key: true, index: { unique: true }
    add_foreign_key :terminal_charges, :ticket_payments
    add_foreign_key :terminal_charges, :check_payments
  end
end
