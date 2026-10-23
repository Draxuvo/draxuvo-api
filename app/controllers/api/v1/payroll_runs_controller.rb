module Api
  module V1
    # Corridas de nómina (spec 037): preparar, aprobar, pagar y cancelar. Solo administrador y dueño.
    class PayrollRunsController < BaseController
      include Idempotent
      include PayrollAccess

      idempotent :approve, :pay_all
      before_action :set_run, except: %i[index create]

      def index
        runs = current_company.payroll_runs.includes(:payments, :created_by, :approved_by)
        runs = runs.where(status: params[:status]) if PayrollRun.statuses.key?(params[:status].to_s)
        runs = runs.for_year(params[:year])
        runs = apply_sort(runs, allowed: %i[starts_on created_at total_cents], default: :starts_on, default_dir: :desc)
        @pagy, @runs = pagy(runs)
        render json: paginate_response(@pagy, @runs.map { |run| PayrollRunSerializer.new(run).as_json })
      end

      def show
        render json: payroll_run_json(@run)
      end

      def create
        run = Payroll::BuildRun.call(
          company: current_company, user: current_user, period_type: params[:period_type],
          starts_on: parse_payroll_date(params[:starts_on]), ends_on: parse_payroll_date(params[:ends_on])
        )
        render json: payroll_run_json(run), status: :created
      end

      def destroy
        raise Payroll::Error.new(:not_draft) unless @run.draft?

        @run.destroy!
        head :no_content
      end

      def refresh_employees
        render json: payroll_run_json(Payroll::RefreshEmployees.call(run: @run, user: current_user))
      end

      def approve
        run = Payroll::Approve.call(run: @run, user: current_user, lock_version: params[:lock_version])
        render json: payroll_run_json(run)
      end

      def cancel
        render json: payroll_run_json(Payroll::Cancel.call(run: @run, user: current_user, reason: params[:reason]))
      end

      def pay_all
        ids = params[:payment_ids].presence && Array(params[:payment_ids]).map(&:to_i)
        run, = Payroll::Pay.call(
          run: @run, user: current_user, payment_method: params[:method],
          paid_on: parse_paid_on(params[:paid_on]), reference: params[:reference], payments: ids
        )
        render json: payroll_run_json(run)
      end

      def export
        send_data Payroll::CsvExport.call(@run), type: "text/csv; charset=utf-8",
                  filename: "nomina-#{@run.starts_on}-#{@run.ends_on}.csv"
      end

      private

      def set_run
        @run = current_company.payroll_runs.find(params[:id])
      end

      def parse_paid_on(value)
        value.present? ? parse_payroll_date(value) : nil
      end
    end
  end
end
