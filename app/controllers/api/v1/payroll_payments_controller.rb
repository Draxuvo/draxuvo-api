module Api
  module V1
    # Líneas de una corrida (spec 037): días a pagar, quitar una línea, marcar como pagada y ver el recibo.
    class PayrollPaymentsController < BaseController
      include Idempotent
      include PayrollAccess

      idempotent :pay
      before_action :set_payment

      def show
        raise Payroll::Error.new(:not_paid) unless @payment.paid?

        render json: PayrollPaymentSerializer.new(@payment, receipt: true).as_json
      end

      def update
        ActiveRecord::Base.transaction do
          run = PayrollRun.lock.find(@payment.payroll_run_id)
          raise Payroll::Error.new(:not_draft) unless run.draft?
          raise Payroll::Error.new(:stale_object, status: :conflict) unless params[:lock_version].present? && run.lock_version == params[:lock_version].to_i

          @payment.reload.update!(days_paid: params[:days_paid])
          Payroll::Recalculate.payment!(@payment)
          Payroll::RecordEvent.call(run: run, user: current_user, action: :days_changed,
                                    details: { payment_id: @payment.id, employee: @payment.employee_name, days_paid: @payment.days_paid })
        end
        render json: PayrollPaymentSerializer.new(@payment.reload).as_json
      end

      def destroy
        ActiveRecord::Base.transaction do
          run = PayrollRun.lock.find(@payment.payroll_run_id)
          raise Payroll::Error.new(:not_draft) unless run.draft?
          raise Payroll::Error.new(:has_corrections) if @payment.adjustments.where.not(corrects_payment_id: nil).exists?

          @payment.destroy!
          Payroll::Recalculate.run!(run)
          Payroll::RecordEvent.call(run: run, user: current_user, action: :line_removed,
                                    details: { employee: @payment.employee_name })
        end
        head :no_content
      end

      def pay
        run, = Payroll::Pay.call(
          run: @payment.payroll_run, user: current_user, payment_method: params[:method],
          paid_on: params[:paid_on].present? ? parse_payroll_date(params[:paid_on]) : nil,
          reference: params[:reference], payments: [ @payment.id ]
        )
        render json: PayrollPaymentSerializer.new(run.payments.find(@payment.id)).as_json
      end

      private

      def set_payment
        @payment = current_company.payroll_payments.includes(:adjustments, :paid_by, :payroll_run).find(params[:id])
      end
    end
  end
end
