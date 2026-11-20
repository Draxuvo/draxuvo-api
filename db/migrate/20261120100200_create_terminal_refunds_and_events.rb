# Reembolsos de pagos integrados y bitácora de solo inserción (spec 069, data-model.md, FR-029, FR-034).
class CreateTerminalRefundsAndEvents < ActiveRecord::Migration[8.0]
  def change
    create_table :terminal_refunds do |t|
      t.references :company, null: false, foreign_key: true
      t.references :terminal_charge, null: false, foreign_key: true, index: { unique: true }
      t.references :ticket_payment, foreign_key: true
      t.decimal :amount, precision: 10, scale: 2, null: false
      t.string :status, null: false
      t.string :reason
      t.string :provider_refund_id
      t.integer :attempts, null: false, default: 1
      t.string :idempotency_key, null: false
      t.string :error_code
      t.string :error_message
      t.references :requested_by, null: false, foreign_key: { to_table: :users }
      t.datetime :requested_at
      t.datetime :completed_at
      t.timestamps
    end

    create_table :terminal_events do |t|
      t.references :company, foreign_key: true
      t.string :kind, null: false
      t.references :terminal_connection, foreign_key: true
      t.references :payment_terminal, foreign_key: true
      t.references :terminal_charge, foreign_key: true
      t.references :terminal_refund, foreign_key: true
      t.references :user, foreign_key: true
      t.jsonb :data, null: false, default: {}
      t.datetime :created_at, null: false
    end
    add_index :terminal_events, %i[company_id created_at]
  end
end
