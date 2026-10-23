module Payroll
  # «Actualizar empleados» (spec 037, edge cases): agrega los activos con salario que faltan y quita las líneas sin ajustes de
  # quienes ya no están activos. Solo en borrador.
  class RefreshEmployees
    def self.call(**args) = new(**args).call

    def initialize(run:, user:)
      @run = run
      @user = user
    end

    def call
      ActiveRecord::Base.transaction do
        run = PayrollRun.lock.find(@run.id)
        raise Error.new(:not_draft) unless run.draft?

        added = Lines.new(run).add_missing!
        stale = run.payments.left_joins(:employee, :adjustments)
                   .where("employees.id IS NULL OR employees.status = ?", Employee.statuses[:inactive])
                   .where(payroll_adjustments: { id: nil })
        removed = stale.pluck(:id).uniq
        run.payments.where(id: removed).destroy_all
        Recalculate.run!(run)
        RecordEvent.call(run: run, user: @user, action: :employees_refreshed, details: { added: added, removed: removed.size })
        run
      end
    end
  end
end
