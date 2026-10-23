module Payroll
  # Escribe una línea en la bitácora de la corrida (spec 037, FR-015); siempre dentro de la transacción del cambio.
  class RecordEvent
    def self.call(run:, user:, action:, details: {})
      PayrollEvent.create!(company_id: run.company_id, payroll_run: run, user: user, action: action.to_s,
                           details: details, created_at: Time.current)
    end
  end
end
