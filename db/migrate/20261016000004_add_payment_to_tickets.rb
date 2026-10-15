# El cobro vive en el ticket (spec 007, R4). status: 0 pending, 1 paid, 2 voided.
class AddPaymentToTickets < ActiveRecord::Migration[8.0]
  def change
    add_column :tickets, :payment_method, :integer
    add_column :tickets, :amount_received, :decimal, precision: 10, scale: 2
    add_column :tickets, :change_given, :decimal, precision: 10, scale: 2
    add_reference :tickets, :charged_by, polymorphic: true
    add_column :tickets, :voided_at, :datetime
    add_reference :tickets, :voided_by, polymorphic: true
    add_column :tickets, :void_reason, :text
  end
end
