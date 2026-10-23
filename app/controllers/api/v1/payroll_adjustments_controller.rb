module Api
  module V1
    # Ajustes (bonos y deducciones) de una línea en borrador (spec 037, FR-007 y FR-013).
    class PayrollAdjustmentsController < BaseController
      include PayrollAccess

      def create
        payment = current_company.payroll_payments.find(params[:payroll_payment_id])
        adjustment = change(payment, :adjustment_added) do
          record = payment.adjustments.new(adjustment_params.merge(company: current_company, created_by: current_user))
          if params[:corrects_payment_id].present?
            record.corrects_payment = current_company.payroll_payments.find(params[:corrects_payment_id])
          end
          record.save!
          record
        end
        render json: PayrollAdjustmentSerializer.new(adjustment).as_json, status: :created
      end

      def update
        adjustment = current_company.payroll_adjustments.find(params[:id])
        adjustment = change(adjustment.payroll_payment, :adjustment_updated) do
          adjustment.update!(adjustment_params)
          adjustment
        end
        render json: PayrollAdjustmentSerializer.new(adjustment).as_json
      end

      def destroy
        adjustment = current_company.payroll_adjustments.find(params[:id])
        change(adjustment.payroll_payment, :adjustment_removed) do
          adjustment.destroy!
          adjustment
        end
        head :no_content
      end

      private

      def adjustment_params
        params.permit(:kind, :amount_cents, :note)
      end

      # Todo cambio de ajustes: solo con la corrida en borrador, recalcula la línea y deja evento.
      def change(payment, action)
        ActiveRecord::Base.transaction do
          run = PayrollRun.lock.find(payment.payroll_run_id)
          raise Payroll::Error.new(:not_draft) unless run.draft?

          result = yield
          Payroll::Recalculate.payment!(payment.reload)
          Payroll::RecordEvent.call(run: run, user: current_user, action: action,
                                    details: { employee: payment.employee_name, kind: result.kind,
                                               amount_cents: result.amount_cents, note: result.note })
          result
        end
      end
    end
  end
end
