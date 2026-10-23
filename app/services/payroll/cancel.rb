module Payroll
  # Cancela una corrida aprobada sin pagos, con motivo (spec 037, FR-014).
  class Cancel
    def self.call(**args) = new(**args).call

    def initialize(run:, user:, reason:)
      @run = run
      @user = user
      @reason = reason.to_s.strip
    end

    def call
      raise Error.new(:reason_required) if @reason.blank?

      ActiveRecord::Base.transaction do
        run = PayrollRun.lock.find(@run.id)
        raise Error.new(:has_payments) if run.payments.paid.exists?
        raise Error.new(:not_approved) unless run.approved?

        run.update!(status: :cancelled, cancelled_by: @user, cancelled_at: Time.current, cancel_reason: @reason)
        RecordEvent.call(run: run, user: @user, action: :cancelled, details: { reason: @reason })
        run
      end
    end
  end
end
