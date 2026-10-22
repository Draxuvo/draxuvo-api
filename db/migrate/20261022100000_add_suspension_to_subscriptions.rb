# Suspensión por falta de pago (spec 031): columnas de la suscripción y registro de cambios.
class AddSuspensionToSubscriptions < ActiveRecord::Migration[8.0]
  def up
    change_table :subscriptions do |t|
      t.datetime :past_due_since
      t.datetime :suspended_at
      t.string :suspension_reason
      t.string :pending_invoice_url
      t.datetime :past_due_notice_sent_at
      t.datetime :cancel_warning_sent_at
    end

    create_table :subscription_changes do |t|
      t.references :company, null: false, foreign_key: true
      t.references :subscription, null: false, foreign_key: true
      t.references :actor, foreign_key: { to_table: :users }
      t.string :kind, null: false
      t.string :from_plan
      t.string :to_plan
      t.string :reason
      t.datetime :created_at, null: false
    end

    # Las past_due de hoy empiezan su gracia de 7 días ahora, no las suspende de golpe.
    execute "UPDATE subscriptions SET past_due_since = NOW() WHERE status = 2"
  end

  def down
    drop_table :subscription_changes
    change_table :subscriptions do |t|
      t.remove :past_due_since, :suspended_at, :suspension_reason, :pending_invoice_url,
               :past_due_notice_sent_at, :cancel_warning_sent_at
    end
  end
end
