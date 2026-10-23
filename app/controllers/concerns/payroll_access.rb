# Acceso a la nómina (spec 037): módulo de empleados y rol administrador, dueño o super admin (FR-001 y FR-002).
# Los errores de negocio de Payroll::Error salen con la forma de ApiErrors.
module PayrollAccess
  extend ActiveSupport::Concern

  included do
    requires_module :employees
    before_action :require_admin!
    rescue_from Payroll::Error, with: :handle_payroll_error
    rescue_from ActiveRecord::StaleObjectError, with: -> { handle_payroll_error(Payroll::Error.new(:stale_object, status: :conflict)) }
  end

  private

  def handle_payroll_error(error)
    api_error = ApiErrors::BaseError.new(status: error.status, message: I18n.t("payroll.errors.#{error.code}"),
                                         details: error.details)
    render json: api_error.as_json, status: error.status
  end

  def payroll_run_json(run)
    PayrollRunSerializer.new(PayrollRun.includes(payments: %i[adjustments paid_by], created_by: [], approved_by: []).find(run.id), detail: true).as_json
  end

  def parse_payroll_date(value)
    Date.iso8601(value.to_s)
  rescue ArgumentError
    raise Payroll::Error.new(:period_invalid)
  end
end
