# Spec 054 (H-50): historial de anulaciones del cobro de un ticket. Una orden anulada y vuelta a cobrar conserva el folio
# (spec 007), así que cada anulación deja aquí quién, cuándo, por qué y qué pagos se anularon. Solo inserción.
class CreateTicketVoids < ActiveRecord::Migration[8.0]
  def change
    create_table :ticket_voids do |t|
      t.references :company, null: false, foreign_key: true
      t.references :ticket, null: false, foreign_key: true
      t.references :voided_by, null: false, foreign_key: { to_table: :users }
      t.datetime :voided_at, null: false
      t.string :reason, null: false
      t.decimal :amount, precision: 10, scale: 2, null: false
      t.jsonb :payments, null: false, default: []
      t.timestamps
    end
  end
end
