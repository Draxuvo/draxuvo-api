# Pagos del cobro de una orden (spec 015, R1) y terminal y origen en los pagos de cuenta.
class CreateTicketPayments < ActiveRecord::Migration[8.0]
  def change
    create_table :ticket_payments do |t|
      t.references :company, null: false, foreign_key: true
      t.references :ticket, null: false, foreign_key: true
      t.integer :payment_method, null: false
      t.decimal :amount, precision: 10, scale: 2, null: false
      t.decimal :amount_received, precision: 10, scale: 2
      t.decimal :change_given, precision: 10, scale: 2
      t.references :terminal, foreign_key: { to_table: :payment_terminals }
      t.string :authorization_code
      t.string :card_last4, limit: 4
      t.string :reference
      t.integer :source, null: false, default: 0
      t.references :created_by, null: false, foreign_key: { to_table: :users }
      t.datetime :voided_at
      t.timestamps
    end

    add_reference :check_payments, :terminal, foreign_key: { to_table: :payment_terminals }
    add_column :check_payments, :source, :integer, null: false, default: 0
  end
end
