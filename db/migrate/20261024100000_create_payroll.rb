# Spec 037: pago de nómina. Corridas por periodo, una línea de pago por empleado, ajustes (bonos y deducciones)
# y la bitácora de lo que se hizo. Montos en centavos MXN.
class CreatePayroll < ActiveRecord::Migration[8.0]
  def change
    create_table :payroll_runs do |t|
      t.references :company, null: false, foreign_key: true
      t.integer :period_type, null: false
      t.date :starts_on, null: false
      t.date :ends_on, null: false
      t.integer :status, null: false, default: 0
      t.integer :lock_version, null: false, default: 0
      t.bigint :total_cents, null: false, default: 0
      t.references :created_by, null: false, foreign_key: { to_table: :users }
      t.references :approved_by, foreign_key: { to_table: :users }
      t.references :cancelled_by, foreign_key: { to_table: :users }
      t.datetime :approved_at
      t.datetime :cancelled_at
      t.text :cancel_reason
      t.timestamps
    end
    add_index :payroll_runs, %i[company_id starts_on], order: { starts_on: :desc }
    add_index :payroll_runs, %i[company_id status]

    create_table :payroll_payments do |t|
      t.references :company, null: false, foreign_key: true
      t.references :payroll_run, null: false, foreign_key: true
      t.references :employee, foreign_key: { on_delete: :nullify }
      t.string :employee_name, null: false
      t.bigint :monthly_salary_cents, null: false, default: 0
      t.integer :period_days, null: false
      t.integer :days_paid, null: false
      t.bigint :salary_cents, null: false, default: 0
      t.bigint :bonus_cents, null: false, default: 0
      t.bigint :deduction_cents, null: false, default: 0
      t.bigint :net_cents, null: false, default: 0
      t.integer :days_attended, null: false, default: 0
      t.decimal :hours_worked, precision: 8, scale: 2, null: false, default: 0
      t.integer :status, null: false, default: 0
      t.integer :payment_method
      t.string :reference, limit: 80
      t.date :paid_on
      t.references :paid_by, foreign_key: { to_table: :users }
      t.datetime :paid_at
      t.timestamps
    end
    add_index :payroll_payments, %i[payroll_run_id employee_id], unique: true

    create_table :payroll_adjustments do |t|
      t.references :company, null: false, foreign_key: true
      t.references :payroll_payment, null: false, foreign_key: true
      t.integer :kind, null: false
      t.bigint :amount_cents, null: false
      t.string :note, null: false, limit: 200
      t.references :corrects_payment, foreign_key: { to_table: :payroll_payments }
      t.references :created_by, null: false, foreign_key: { to_table: :users }
      t.timestamps
    end

    create_table :payroll_events do |t|
      t.references :company, null: false, foreign_key: true
      t.references :payroll_run, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.string :action, null: false
      t.jsonb :details, null: false, default: {}
      t.datetime :created_at, null: false
    end
  end
end
