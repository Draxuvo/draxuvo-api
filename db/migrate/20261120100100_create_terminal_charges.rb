# Solicitud de cobro en una terminal integrada (spec 069, data-model.md): vive minutos y, si el proveedor aprueba, genera
# el pago con los servicios de cobro de siempre.
class CreateTerminalCharges < ActiveRecord::Migration[8.0]
  OPEN = "status IN ('pending','canceling')".freeze

  def change
    create_table :terminal_charges do |t|
      t.references :company, null: false, foreign_key: true
      t.references :payment_terminal, null: false, foreign_key: true, index: false
      t.references :terminal_connection, null: false, foreign_key: true
      t.references :work_order, foreign_key: true, index: false
      t.references :sale, foreign_key: true, index: false
      t.references :check, foreign_key: true, index: false
      t.references :created_by, null: false, foreign_key: { to_table: :users }
      t.decimal :amount, precision: 10, scale: 2, null: false
      t.jsonb :params, null: false, default: {}
      t.string :status, null: false, default: "pending"
      t.string :status_detail
      t.string :external_reference, null: false
      t.uuid :idempotency_key, null: false
      t.string :provider_order_id
      t.string :provider_payment_id
      t.string :provider_reference
      t.string :card_last4, limit: 4
      t.string :payment_type
      t.datetime :expires_at, null: false
      t.datetime :last_synced_at
      t.datetime :resolved_at
      t.datetime :applied_at
      t.datetime :cancel_requested_at
      t.string :unapplied_reason
      t.bigint :ticket_payment_id
      t.bigint :check_payment_id
      t.integer :lock_version, null: false, default: 0
      t.timestamps
    end

    add_check_constraint :terminal_charges,
                         "(work_order_id IS NOT NULL)::int + (sale_id IS NOT NULL)::int + (check_id IS NOT NULL)::int = 1",
                         name: "terminal_charges_one_owner"
    add_check_constraint :terminal_charges, "amount > 0", name: "terminal_charges_amount_positive"

    add_index :terminal_charges, :external_reference, unique: true
    add_index :terminal_charges, :provider_order_id, unique: true
    # Una terminal y un cobro atienden una sola solicitud abierta a la vez (FR-016, research R9).
    add_index :terminal_charges, :payment_terminal_id, unique: true, where: OPEN, name: "index_terminal_charges_open_terminal"
    add_index :terminal_charges, :payment_terminal_id
    %i[work_order_id sale_id check_id].each do |owner|
      add_index :terminal_charges, owner, unique: true, where: OPEN, name: "index_terminal_charges_open_#{owner}"
      add_index :terminal_charges, owner
    end
    add_index :terminal_charges, %i[status last_synced_at]
    add_index :terminal_charges, %i[company_id status]
  end
end
