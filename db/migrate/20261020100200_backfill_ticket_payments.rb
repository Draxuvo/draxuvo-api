# Un pago por cada ticket de orden cobrado antes de la spec 015 (R3), para que reportes y tickets lean una sola fuente.
class BackfillTicketPayments < ActiveRecord::Migration[8.0]
  def up
    execute <<~SQL
      INSERT INTO ticket_payments (company_id, ticket_id, payment_method, amount, amount_received, change_given,
                                   source, created_by_id, voided_at, created_at, updated_at)
      SELECT t.company_id, t.id, t.payment_method, t.total,
             CASE WHEN t.payment_method = 0 THEN t.amount_received END,
             CASE WHEN t.payment_method = 0 THEN t.change_given END,
             0,
             COALESCE(CASE WHEN t.charged_by_type = 'User' THEN t.charged_by_id END,
                      CASE WHEN w.created_by_type = 'User' THEN w.created_by_id END),
             t.voided_at, COALESCE(t.paid_at, t.created_at), NOW()
      FROM tickets t
      JOIN work_orders w ON w.id = t.work_order_id
      WHERE t.payment_method IS NOT NULL
        AND COALESCE(CASE WHEN t.charged_by_type = 'User' THEN t.charged_by_id END,
                     CASE WHEN w.created_by_type = 'User' THEN w.created_by_id END) IS NOT NULL
    SQL
  end

  def down
    execute "DELETE FROM ticket_payments"
  end
end
